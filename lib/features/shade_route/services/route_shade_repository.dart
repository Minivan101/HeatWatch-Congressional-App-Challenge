import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/models/coordinates.dart';
import 'local_shade_calculator.dart';
import 'route_shade_calculator.dart';

Map<String, dynamic> _runShade(Map<String, dynamic> input) {
  final points = (input['points'] as List)
      .map(
        (p) => Coordinates(
          latitude: (p[0] as num).toDouble(),
          longitude: (p[1] as num).toDouble(),
        ),
      )
      .toList();
  return calculateRouteShade(
    WalkingGeometry(
      points: points,
      durationSeconds: input['duration'] as double,
      sourceUrl: input['sourceUrl'] as String,
      accessReviewed: false,
      segmentSeconds: (input['segmentSeconds'] as List?)?.cast<double>(),
    ),
    DateTime.parse(input['departure'] as String),
    RouteShadeData(
      input['manifest'] as Map<String, dynamic>,
      (input['buildings'] as Map).cast<String, Uint8List>(),
      (input['canopy'] as Map).cast<String, Uint8List>(),
    ),
  );
}

// shade data
class RouteShadeRepository {
  RouteShadeRepository({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;
  final AssetBundle bundle;
  Future<Map<String, dynamic>>? _manifest;
  final _cache = <String, Uint8List>{};
  int _cachedBytes = 0;
  static const base = 'data/shade/las_vegas/';
  Future<Uint8List> _load(String path) async {
    final hit = _cache.remove(path);
    if (hit != null) {
      _cache[path] = hit;
      return hit;
    }
    final data = await bundle.load(base + path);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    _cache[path] = bytes;
    _cachedBytes += bytes.length;
    while (_cachedBytes > 8 * 1024 * 1024 && _cache.length > 1) {
      final key = _cache.keys.first;
      _cachedBytes -= _cache.remove(key)!.length;
    }
    return bytes;
  }

  Future<Map<String, dynamic>> calculate(
    WalkingGeometry route,
    DateTime departure,
  ) async {
    _manifest ??= bundle
        .loadString('${base}manifest.json')
        .then((s) => jsonDecode(s) as Map<String, dynamic>);
    final manifest = await _manifest!;
    final projected = route.points.map(shadeProject).toList();
    if (projected.isEmpty) {
      throw const FormatException('Choose a walking path first.');
    }

    final keys = <String>{};
    for (var i = 1; i < projected.length; i++) {
      final a = projected[i - 1], b = projected[i];
      final pieces = (math.max((b.x - a.x).abs(), (b.y - a.y).abs()) / 1280)
          .ceil()
          .clamp(1, 10000);
      for (var j = 0; j < pieces; j++) {
        final x0 = a.x + (b.x - a.x) * j / pieces;
        final y0 = a.y + (b.y - a.y) * j / pieces;
        final x1 = a.x + (b.x - a.x) * (j + 1) / pieces;
        final y1 = a.y + (b.y - a.y) * (j + 1) / pieces;

        for (
          var x = ((math.min(x0, x1) - 350) / 2560).floor();
          x <= ((math.max(x0, x1) + 350) / 2560).floor();
          x++
        ) {
          for (
            var y = ((math.min(y0, y1) - 350) / 2560).floor();
            y <= ((math.max(y0, y1) + 350) / 2560).floor();
            y++
          ) {
            keys.add('${x}_$y');
          }
        }
      }
    }
    final buildings = <String, Uint8List>{}, canopy = <String, Uint8List>{};
    final tiles = manifest['tiles'] as Map;
    for (final key in keys) {
      final t = tiles[key];
      if (t == null) continue;
      buildings[key] = await _load(t['buildings'] as String);
      canopy[key] = await _load(t['canopy'] as String);
    }
    return compute(_runShade, {
      'manifest': manifest,
      'buildings': buildings,
      'canopy': canopy,
      'points': route.points.map((p) => [p.latitude, p.longitude]).toList(),
      'duration': route.durationSeconds,
      'segmentSeconds': route.segmentSeconds,
      'sourceUrl': route.sourceUrl,
      'departure': departure.toUtc().toIso8601String(),
    });
  }
}
