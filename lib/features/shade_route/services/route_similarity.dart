import 'dart:math' as math;

import '../../../core/models/coordinates.dart';
import 'city_trip_service.dart';

// route overlap
bool routesMostlyOverlap(CityWalkingRoute a, CityWalkingRoute b) {
  if (identical(a, b)) return true;
  final origin = a.geometry.points.firstOrNull;
  if (origin == null) return false;
  final scale = math.cos(origin.latitude * math.pi / 180);
  List<({double x, double y})> project(List<Coordinates> points) => [
    for (final p in points)
      (
        x: (p.longitude - origin.longitude) * 111320 * scale,
        y: (p.latitude - origin.latitude) * 111320,
      ),
  ];
  final first = project(a.geometry.points), second = project(b.geometry.points);
  double shared(
    List<({double x, double y})> route,
    List<({double x, double y})> other,
  ) {
    if (route.length < 2 || other.length < 2) return 0;
    final lengths = <double>[];
    var total = 0.0;
    for (var i = 1; i < route.length; i++) {
      final dx = route[i].x - route[i - 1].x;
      final dy = route[i].y - route[i - 1].y;
      final length = math.sqrt(dx * dx + dy * dy);
      lengths.add(length);
      total += length;
    }
    if (!total.isFinite || total <= 0) return 0;
    final samples = (total / 5).ceil().clamp(1, 512);
    var matched = 0, segment = 0;
    var before = 0.0;
    for (var sample = 0; sample < samples; sample++) {
      final distance = (sample + .5) * total / samples;
      while (segment < lengths.length - 1 &&
          before + lengths[segment] < distance) {
        before += lengths[segment++];
      }
      final t = lengths[segment] == 0
          ? 0.0
          : (distance - before) / lengths[segment];
      final x =
          route[segment].x + (route[segment + 1].x - route[segment].x) * t;
      final y =
          route[segment].y + (route[segment + 1].y - route[segment].y) * t;
      for (var j = 1; j < other.length; j++) {
        final p = other[j - 1], q = other[j];
        final dx = q.x - p.x, dy = q.y - p.y;
        final squared = dx * dx + dy * dy;
        final f = squared == 0
            ? 0.0
            : (((x - p.x) * dx + (y - p.y) * dy) / squared).clamp(0.0, 1.0);
        final ex = x - p.x - dx * f, ey = y - p.y - dy * f;
        if (ex * ex + ey * ey <= 100) {
          matched++;
          break;
        }
      }
    }
    return matched / samples;
  }

  return shared(first, second) >= .90 && shared(second, first) >= .90;
}

class RouteOverlapComparison {
  CityWalkingRoute? _first, _second;
  bool _overlap = false;
  bool matches(CityWalkingRoute first, CityWalkingRoute second) {
    if (!identical(first, _first) || !identical(second, _second)) {
      _first = first;
      _second = second;
      _overlap = routesMostlyOverlap(first, second);
    }
    return _overlap;
  }
}
