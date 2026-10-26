import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'walking_limits.dart';
import '../../../core/models/coordinates.dart';
import 'local_shade_calculator.dart';

const _r = 6378137.0, _rad = math.pi / 180, _bin = 100.0;
typedef ShadeXY = ({double x, double y});
ShadeXY shadeProject(Coordinates p) => (
  x: _r * p.longitude * _rad,
  y: _r * math.log(math.tan(math.pi / 4 + p.latitude * _rad / 2)),
);

class RouteShadeData {
  RouteShadeData(
    this.manifest,
    Map<String, Uint8List> buildingFiles,
    Map<String, Uint8List> canopyFiles,
  ) {
    if (manifest['schemaVersion'] != 1 ||
        manifest['crs'] != 'EPSG:3857' ||
        manifest['cellMeters'] != 5 ||
        manifest['tilePixels'] != 512) {
      throw const FormatException('Unsupported shade-data format.');
    }
    for (final entry in buildingFiles.entries) {
      final raw = jsonDecode(
        utf8.decode(GZipDecoder().decodeBytes(entry.value, verify: true)),
      ) as List;
      for (final b in raw) {
        final rings = (b[1] as List)
            .map(
              (r) => (r as List).map((p) {
                final lon = (p[0] as num).toDouble(),
                    lat = (p[1] as num).toDouble();
                if (!lat.isFinite ||
                    !lon.isFinite ||
                    lat.abs() > 70 ||
                    lon.abs() > 180) {
                  throw const FormatException('Invalid building coordinate.');
                }
                return shadeProject(Coordinates(latitude: lat, longitude: lon));
              }).toList(),
            )
            .toList();
        if (rings.isEmpty || rings.any((r) => r.length < 3)) {
          throw const FormatException('Invalid building rings.');
        }
        final h = b[0] == null ? null : (b[0] as num).toDouble();
        if (h != null && (!h.isFinite || h <= 0 || h > 500)) {
          throw const FormatException('Invalid estimated building height.');
        }

        final key = jsonEncode(b[1]);
        if (!_seen.add(key)) continue;
        final building = _Building(h, rings);
        for (
          var x = (building.west / _bin).floor();
          x <= (building.east / _bin).floor();
          x++
        ) {
          for (
            var y = (building.south / _bin).floor();
            y <= (building.north / _bin).floor();
            y++
          ) {
            _index.putIfAbsent('$x:$y', () => []).add(building);
          }
        }
        buildings++;
        if (h != null) heights++;
      }
    }
    for (final entry in canopyFiles.entries) {
      final bytes = Uint8List.fromList(
        GZipDecoder().decodeBytes(entry.value, verify: true),
      );
      if (bytes.length != 512 * 512) {
        throw const FormatException('Invalid canopy tile.');
      }
      _canopy[entry.key] = bytes;
    }
  }
  final Map<String, dynamic> manifest;
  final _seen = <String>{};
  final _index = <String, List<_Building>>{};
  final _canopy = <String, Uint8List>{};
  int buildings = 0, heights = 0;
  Set<_Building> _alongRay(ShadeXY p, double dx, double dy, double distance) {
    final found = <_Building>{};

    final steps = (distance / (_bin / 2)).ceil();
    for (var i = 0; i <= steps; i++) {
      final d = distance * i / steps;
      final bx = ((p.x + dx * d) / _bin).floor(),
          by = ((p.y + dy * d) / _bin).floor();
      for (var ox = -1; ox <= 1; ox++) {
        for (var oy = -1; oy <= 1; oy++) {
          found.addAll(_index['${bx + ox}:${by + oy}'] ?? const []);
        }
      }
    }
    return found;
  }

  int? canopyAt(ShadeXY p) {
    const span = 2560.0;
    final x = (p.x / span).floor(), y = (p.y / span).floor();
    final bytes = _canopy['${x}_$y'];
    if (bytes == null) return null;
    final col = ((p.x - x * span) / 5).floor();
    final row = (((y + 1) * span - p.y) / 5).floor();
    if (row < 0 || row >= 512 || col < 0 || col >= 512) return null;
    final value = bytes[row * 512 + col];
    return value == 255 ? null : value;
  }

  bool covers(Coordinates p) {
    final b = manifest['bounds'];
    final latMargin = 250 / 111195,
        lonMargin = latMargin / math.cos(p.latitude * _rad);
    if (p.latitude - latMargin < b['south'] ||
        p.latitude + latMargin > b['north'] ||
        p.longitude - lonMargin < b['west'] ||
        p.longitude + lonMargin > b['east']) {
      return false;
    }
    for (final raw in manifest['coverageGaps'] as List) {
      if (p.longitude + lonMargin >= raw[0] &&
          p.latitude + latMargin >= raw[1] &&
          p.longitude - lonMargin <= raw[2] &&
          p.latitude - latMargin <= raw[3]) {
        return false;
      }
    }
    return true;
  }
}

bool _inside(ShadeXY p, List<ShadeXY> ring) {
  var hit = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      hit = !hit;
    }
  }
  return hit;
}

class _Building {
  _Building(this.height, this.rings) {
    west = rings.first.map((p) => p.x).reduce(math.min);
    east = rings.first.map((p) => p.x).reduce(math.max);
    south = rings.first.map((p) => p.y).reduce(math.min);
    north = rings.first.map((p) => p.y).reduce(math.max);
  }
  final double? height;
  final List<List<ShadeXY>> rings;
  late final double west, east, south, north;
  bool contains(ShadeXY p) =>
      _inside(p, rings.first) && !rings.skip(1).any((r) => _inside(p, r));
  double? intersection(ShadeXY p, double dx, double dy, double limit) {
    double? nearest;
    for (final ring in rings) {
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], b = ring[(i + 1) % ring.length];
        final ex = b.x - a.x, ey = b.y - a.y;
        final denom = dx * ey - dy * ex;
        if (denom.abs() < 1e-10) continue;
        final ax = a.x - p.x, ay = a.y - p.y;
        final t = (ax * ey - ay * ex) / denom;
        final u = (ax * dy - ay * dx) / denom;
        if (t >= 0 &&
            t <= limit &&
            u >= 0 &&
            u <= 1 &&
            (nearest == null || t < nearest)) {
          nearest = t;
        }
      }
    }
    return nearest;
  }
}

Map<String, dynamic> calculateRouteShade(
  WalkingGeometry route,
  DateTime departure,
  RouteShadeData data,
) {
  if (route.points.length < 2 ||
      route.points.length > 10000 ||
      !route.durationSeconds.isFinite ||
      route.durationSeconds <= 0 ||
      route.durationSeconds > maxWalkingSeconds) {
    throw const FormatException('Use a walking trip of at most twelve hours.');
  }
  final lengths = <double>[];
  var distance = 0.0;
  for (var i = 1; i < route.points.length; i++) {
    final a = route.points[i - 1], b = route.points[i];
    if (![
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ].every((v) => v.isFinite) ||
        a.latitude.abs() > 70 ||
        b.latitude.abs() > 70 ||
        a.longitude.abs() > 180 ||
        b.longitude.abs() > 180) {
      throw const FormatException('Invalid route coordinate.');
    }
    final dy = (b.latitude - a.latitude) * _rad * 6371000;
    final dx =
        (b.longitude - a.longitude) *
        _rad *
        6371000 *
        math.cos((a.latitude + b.latitude) / 2 * _rad);
    final len = math.sqrt(dx * dx + dy * dy);
    lengths.add(len);
    distance += len;
  }
  if (distance <= 0 || distance > maxWalkingMeters) {
    throw const FormatException('Use a nonzero walking route up to 50 km.');
  }
  final totals = <String, double>{
    'building': 0,
    'canopy': 0,
    'open': 0,
    'unknown': 0,
    'night': 0,
  };
  final timeTotals = {for (final key in totals.keys) key: 0.0};
  final durations = route.durationsFor(lengths);
  final segments = <Map<String, dynamic>>[];
  var cumulativeSeconds = 0.0, capped = false;
  for (var i = 0; i < lengths.length; i++) {
    final length = lengths[i];
    final seconds = durations[i];
    if (length == 0 && seconds == 0) continue;
    final n = math.max(1, (length / 8).ceil()), weight = length / n;
    final a = route.points[i], b = route.points[i + 1];
    for (var s = 0; s < n; s++) {
      final f = (s + .5) / n;
      final p = Coordinates(
        latitude: a.latitude + (b.latitude - a.latitude) * f,
        longitude: a.longitude + (b.longitude - a.longitude) * f,
      );
      final at = departure.toUtc().add(
        Duration(
          milliseconds: ((cumulativeSeconds + seconds * f) * 1000).round(),
        ),
      );
      final sun = localSunPosition(at, p);
      String status;
      if (sun.elevation <= 0) {
        status = 'night';
      } else if (!data.covers(p)) {
        status = 'unknown';
      } else {
        final projected = shadeProject(p), scale = math.cos(p.latitude * _rad);
        final dx = math.sin(sun.azimuth * _rad),
            dy = math.cos(sun.azimuth * _rad);
        final tangent = math.tan(sun.elevation * _rad), limit = 250 / scale;
        var buildingHit = false, missing = false, indoors = false;
        for (final obstacle in data._alongRay(projected, dx, dy, limit)) {
          if (obstacle.contains(projected)) {
            indoors = true;
            continue;
          }
          final near = obstacle.intersection(projected, dx, dy, limit);
          if (near == null) continue;
          if (obstacle.height == null) {
            missing = true;
            continue;
          }
          if (obstacle.height! / tangent > 250) capped = true;
          if (near * scale * tangent <= obstacle.height!) buildingHit = true;
        }
        var canopyHit = false;

        final rayLimit = math.min(250.0, 254 / tangent);
        for (var d = 0.0; d <= rayLimit; d += 2) {
          final value = data.canopyAt((
            x: projected.x + dx * d / scale,
            y: projected.y + dy * d / scale,
          ));
          if (value == null) {
            missing = true;
            continue;
          }
          if (value >= 2 && value > d * tangent) {
            canopyHit = true;
            break;
          }
        }
        status = indoors
            ? 'unknown'
            : buildingHit
            ? 'building'
            : canopyHit
            ? 'canopy'
            : missing
            ? 'unknown'
            : 'open';
      }
      totals[status] = totals[status]! + weight;
      timeTotals[status] = timeTotals[status]! + seconds / n;
      final startF = s / n, endF = (s + 1) / n;
      final from = [
        a.latitude + (b.latitude - a.latitude) * startF,
        a.longitude + (b.longitude - a.longitude) * startF,
      ];
      final to = [
        a.latitude + (b.latitude - a.latitude) * endF,
        a.longitude + (b.longitude - a.longitude) * endF,
      ];
      if (segments.isNotEmpty &&
          segments.last['kind'] == status &&
          (segments.last['points'] as List).last[0] == from[0] &&
          (segments.last['points'] as List).last[1] == from[1]) {
        (segments.last['points'] as List).add(to);
      } else {
        segments.add({
          'kind': status,
          'points': [from, to],
        });
      }
    }
    cumulativeSeconds += seconds;
  }
  final available = totals['building']! + totals['canopy']! + totals['open']!;
  final daylight = available + totals['unknown']!;
  final arrival = departure.toUtc().add(
    Duration(milliseconds: (route.durationSeconds * 1000).round()),
  );
  final startSun = localSunPosition(departure, route.points.first);
  final endSun = localSunPosition(arrival, route.points.last);
  return {
    'sunAtDeparture': {
      'elevation': startSun.elevation,
      'azimuth': startSun.azimuth,
    },
    'sunAtArrival': {'elevation': endSun.elevation, 'azimuth': endSun.azimuth},
    'shade': daylight > 0 && available > 0
        ? (totals['building']! + totals['canopy']!) / daylight
        : null,
    'buildingShade': daylight > 0 ? totals['building']! / daylight : null,
    'canopyShade': daylight > 0 ? totals['canopy']! / daylight : null,
    'coverage': daylight > 0 ? available / daylight : null,
    'night': totals['night'],
    'distance': distance,
    'heights': data.heights,
    'footprints': data.buildings,
    'duration': route.durationSeconds,
    'departure': departure.toUtc().toIso8601String(),
    'arrival': departure
        .toUtc()
        .add(Duration(milliseconds: (route.durationSeconds * 1000).round()))
        .toIso8601String(),
    'totals': totals,
    'timeTotals': timeTotals,
    'timingModel': route.segmentSeconds == null
        ? 'uniform-average-pace'
        : 'provider-segment-proportions',
    'cappedShadows': capped,
    'segments': segments,
  };
}
