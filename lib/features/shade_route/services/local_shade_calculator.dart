import 'dart:math' as math;

import 'walking_limits.dart';
import '../../../core/models/coordinates.dart';

const _deg = math.pi / 180;
typedef _Point = ({double x, double y});

void _validate(Coordinates p) {
  if (!p.latitude.isFinite ||
      !p.longitude.isFinite ||
      p.latitude.abs() > 70 ||
      p.longitude.abs() > 180) {
    throw const FormatException(
      'Invalid coordinate or outside local model latitude range.',
    );
  }
}

Coordinates _coordinate(dynamic raw) {
  final p = Coordinates(
    latitude: (raw['latitude'] as num).toDouble(),
    longitude: (raw['longitude'] as num).toDouble(),
  );
  _validate(p);
  return p;
}

_Point _project(Coordinates p, Coordinates ref) => (
  x:
      (p.longitude - ref.longitude) *
      _deg *
      6371000 *
      math.cos(ref.latitude * _deg),
  y: (p.latitude - ref.latitude) * _deg * 6371000,
);

({double elevation, double azimuth}) localSunPosition(
  DateTime time,
  Coordinates p,
) {
  _validate(p);
  final at = time.toUtc();
  final yearDays = DateTime.utc(at.year + 1)
      .difference(DateTime.utc(at.year))
      .inDays;
  final day =
      DateTime.utc(
        at.year,
        at.month,
        at.day,
      ).difference(DateTime.utc(at.year)).inDays +
      1;
  final hour = at.hour + at.minute / 60 + at.second / 3600;
  final g = 2 * math.pi / yearDays * (day - 1 + (hour - 12) / 24);
  final eq =
      229.18 *
      (0.000075 +
          0.001868 * math.cos(g) -
          0.032077 * math.sin(g) -
          0.014615 * math.cos(2 * g) -
          0.040849 * math.sin(2 * g));
  final dec =
      0.006918 -
      0.399912 * math.cos(g) +
      0.070257 * math.sin(g) -
      0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) -
      0.002697 * math.cos(3 * g) +
      0.00148 * math.sin(3 * g);
  final solarMinutes = (hour * 60 + eq + 4 * p.longitude) % 1440;
  final ha = (solarMinutes / 4 - 180) * _deg;
  final lat = p.latitude * _deg;
  final elevation =
      math.asin(
        (math.sin(lat) * math.sin(dec) +
                math.cos(lat) * math.cos(dec) * math.cos(ha))
            .clamp(-1, 1),
      ) /
      _deg;
  final azimuth =
      (math.atan2(
                math.sin(ha),
                math.cos(ha) * math.sin(lat) - math.tan(dec) * math.cos(lat),
              ) /
              _deg +
          180) %
      360;
  return (elevation: elevation, azimuth: azimuth);
}

bool _inside(_Point p, List<_Point> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[j], b = polygon[i];
    final cross = (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x);
    if (cross.abs() < 1e-7 &&
        p.x >= math.min(a.x, b.x) - 1e-7 &&
        p.x <= math.max(a.x, b.x) + 1e-7 &&
        p.y >= math.min(a.y, b.y) - 1e-7 &&
        p.y <= math.max(a.y, b.y) + 1e-7) {
      return true;
    }
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

// building shade
bool buildingShadowContains(
  Coordinates sample,
  List<Coordinates> footprint,
  double height,
  double elevation,
  double azimuth,
) {
  _validate(sample);
  if (footprint.length < 3 ||
      !height.isFinite ||
      height <= 0 ||
      height > 500 ||
      !elevation.isFinite ||
      elevation > 90 ||
      elevation < -90 ||
      !azimuth.isFinite) {
    throw const FormatException('Invalid building shadow inputs.');
  }
  footprint.forEach(_validate);
  if (elevation <= 0) return false;
  final polygon = footprint.map((p) => _project(p, sample)).toList();
  const origin = (x: 0.0, y: 0.0);

  if (_inside(origin, polygon)) return false;
  final length = math.min(250.0, height / math.tan(elevation * _deg));
  final dx = -length * math.sin(azimuth * _deg),
      dy = -length * math.cos(azimuth * _deg);
  final shifted = polygon.map((p) => (x: p.x + dx, y: p.y + dy)).toList();
  if (_inside(origin, shifted)) return true;
  for (var i = 0; i < polygon.length; i++) {
    final j = (i + 1) % polygon.length;
    if (_inside(origin, [polygon[i], polygon[j], shifted[j], shifted[i]])) {
      return true;
    }
  }
  return false;
}

class LocalShadeBuildings {
  LocalShadeBuildings(this.data) {
    if (data['schemaVersion'] != 1 ||
        data['buildings'] is! List ||
        data['bounds'] is! Map ||
        data['coverageGaps'] is! List) {
      throw const FormatException('Invalid building dataset.');
    }
    final bounds = data['bounds'];
    for (final key in ['south', 'north', 'west', 'east']) {
      final value = bounds[key];
      if (value is! num || !value.isFinite) {
        throw const FormatException('Invalid dataset bounds.');
      }
    }
    if (bounds['south'] >= bounds['north'] ||
        bounds['west'] >= bounds['east'] ||
        bounds['south'] < -70 ||
        bounds['north'] > 70 ||
        bounds['west'] < -180 ||
        bounds['east'] > 180) {
      throw const FormatException('Invalid dataset bounds.');
    }
    for (final b in buildings) {
      if (b['footprint'] is! List || (b['footprint'] as List).length < 3) {
        throw const FormatException('Invalid footprint.');
      }
      (b['footprint'] as List).map(_coordinate).toList();
      final h = b['heightMeters'];
      if (h != null && (h is! num || !h.isFinite || h <= 0 || h > 500)) {
        throw const FormatException('Invalid height.');
      }
    }
  }
  final Map<String, dynamic> data;
  List<dynamic> get buildings => data['buildings'] as List;
  int get explicitHeights =>
      buildings.where((b) => b['heightSource'] == 'height').length;
  int get levelEstimates =>
      buildings.where((b) => b['heightSource'] == 'building:levels').length;
  int get unknownHeights =>
      buildings.where((b) => b['heightMeters'] == null).length;

  void requireCoverage(List<Coordinates> points) {
    final bounds = data['bounds'];
    for (final p in points) {
      _validate(p);
      final latMargin = 250 / 111195,
          lonMargin = 250 / (111195 * math.cos(p.latitude * _deg));
      if (p.latitude - latMargin < bounds['south'] ||
          p.latitude + latMargin > bounds['north'] ||
          p.longitude - lonMargin < bounds['west'] ||
          p.longitude + lonMargin > bounds['east']) {
        throw const FormatException(
          'Route is outside the buffered building extract.',
        );
      }
      for (final gap in data['coverageGaps']) {
        final b = gap['bounds'];
        if (b == null ||
            (p.latitude + latMargin >= b['south'] &&
                p.latitude - latMargin <= b['north'] &&
                p.longitude + lonMargin >= b['west'] &&
                p.longitude - lonMargin <= b['east'])) {
          throw const FormatException(
            'Incomplete building geometry intersects the route.',
          );
        }
      }
    }
  }
}

class WalkingGeometry {
  const WalkingGeometry({
    required this.points,
    required this.durationSeconds,
    required this.sourceUrl,
    required this.accessReviewed,
    this.segmentSeconds,
  });
  final List<Coordinates> points;
  final double durationSeconds;
  final String sourceUrl;
  final bool accessReviewed;

  final List<double>? segmentSeconds;

  List<double> durationsFor(List<double> lengths) {
    final weights = segmentSeconds ?? lengths;
    if (weights.length != lengths.length ||
        weights.any((v) => !v.isFinite || v < 0)) {
      throw const FormatException('Invalid walking segment timing.');
    }
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (!total.isFinite || total <= 0) {
      throw const FormatException('Invalid walking segment timing.');
    }
    return weights.map((w) => durationSeconds * w / total).toList();
  }

  factory WalkingGeometry.fromOrsFeature(
    Map<String, dynamic> feature, {
    required String profile,
    required bool accessReviewed,
  }) {
    if (profile != 'foot-walking' ||
        feature['geometry']?['type'] != 'LineString') {
      throw const FormatException('Requires a walking LineString.');
    }
    final points = (feature['geometry']['coordinates'] as List).map((c) {
      final p = Coordinates(
        latitude: (c[1] as num).toDouble(),
        longitude: (c[0] as num).toDouble(),
      );
      _validate(p);
      return p;
    }).toList();
    return WalkingGeometry(
      points: points,
      durationSeconds: (feature['properties']['summary']['duration'] as num)
          .toDouble(),
      sourceUrl:
          'https://api.openrouteservice.org/v2/directions/foot-walking/geojson',
      accessReviewed: accessReviewed,
    );
  }
}

class LocalShadeResult {
  const LocalShadeResult({
    required this.distanceMeters,
    required this.modeledShadedMeters,
    required this.daylightMeters,
    required this.nightMeters,
    required this.samples,
    required this.hasModeledHeights,
    required this.cappedShadows,
  });
  final double distanceMeters, modeledShadedMeters, daylightMeters, nightMeters;
  final int samples;
  final bool hasModeledHeights, cappedShadows;

  double? get modeledShadeFraction => !hasModeledHeights || daylightMeters == 0
      ? null
      : modeledShadedMeters / daylightMeters;
}

class LocalShadeCalculator {
  const LocalShadeCalculator();
  LocalShadeResult calculate(
    WalkingGeometry route,
    LocalShadeBuildings dataset,
    DateTime departure, {
    bool allowLevelEstimates = false,
  }) {
    if (route.points.length < 2 ||
        route.points.length > 10000 ||
        !route.durationSeconds.isFinite ||
        route.durationSeconds <= 0 ||
        route.durationSeconds > maxWalkingSeconds ||
        Uri.tryParse(route.sourceUrl)?.scheme != 'https') {
      throw const FormatException('Invalid sourced local walking route.');
    }
    dataset.requireCoverage(route.points);
    final lengths = <double>[];
    var distance = 0.0;
    for (var i = 1; i < route.points.length; i++) {
      final delta = _project(route.points[i], route.points[i - 1]);
      final len = math.sqrt(delta.x * delta.x + delta.y * delta.y);
      lengths.add(len);
      distance += len;
    }
    if (distance <= 0 || distance > maxWalkingMeters) {
      throw const FormatException(
        'Requires a nonzero local route up to 50 km.',
      );
    }
    final usable = dataset.buildings
        .where(
          (b) =>
              b['heightMeters'] != null &&
              (b['heightSource'] == 'height' ||
                  (allowLevelEstimates &&
                      b['heightSource'] == 'building:levels')),
        )
        .toList();
    var shaded = 0.0, daylight = 0.0, night = 0.0, cumulative = 0.0;
    var count = 0, capped = false;
    for (var i = 0; i < lengths.length; i++) {
      final length = lengths[i];
      if (length == 0) continue;
      final n = (length / 10).ceil();
      final weight = length / n;
      for (var s = 0; s < n; s++) {
        final f = (s + 0.5) / n, a = route.points[i], b = route.points[i + 1];
        final p = Coordinates(
          latitude: a.latitude + (b.latitude - a.latitude) * f,
          longitude: a.longitude + (b.longitude - a.longitude) * f,
        );
        dataset.requireCoverage([p]);
        final at = departure.toUtc().add(
          Duration(
            milliseconds:
                (route.durationSeconds *
                        (cumulative + length * f) /
                        distance *
                        1000)
                    .round(),
          ),
        );
        final sun = localSunPosition(at, p);
        count++;
        if (sun.elevation <= 0) {
          night += weight;
          continue;
        }
        daylight += weight;
        var hit = false;
        for (final building in usable) {
          final h = (building['heightMeters'] as num).toDouble();
          if (h / math.tan(sun.elevation * _deg) > 250) capped = true;
          if (buildingShadowContains(
            p,
            (building['footprint'] as List).map(_coordinate).toList(),
            h,
            sun.elevation,
            sun.azimuth,
          )) {
            hit = true;
          }
        }
        if (hit) shaded += weight;
      }
      cumulative += length;
    }
    return LocalShadeResult(
      distanceMeters: distance,
      modeledShadedMeters: shaded,
      daylightMeters: daylight,
      nightMeters: night,
      samples: count,
      hasModeledHeights: usable.isNotEmpty,
      cappedShadows: capped,
    );
  }
}
