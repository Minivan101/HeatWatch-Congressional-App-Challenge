import 'dart:math' as math;

import '../../../core/models/coordinates.dart';
import 'city_trip_service.dart';
import 'walking_navigation.dart';

int? matchingWalkingCorridor(
  List<CityWalkingRoute> candidates,
  CityWalkingRoute previous,
  double along,
) {
  final points = previous.geometry.points;
  final lengths = [
    for (var i = 1; i < points.length; i++)
      walkingDistance(points[i - 1], points[i]),
  ];
  final total = lengths.fold<double>(0, (a, b) => a + b);
  if (total <= 0 || candidates.isEmpty) return null;
  final begin = along.clamp(0.0, total);
  final probes = <Coordinates>[];
  for (var n = 0; n < 32; n++) {
    final target = begin + (total - begin) * (n + .5) / 32;
    var distance = 0.0;
    for (var i = 0; i < lengths.length; i++) {
      final length = lengths[i];
      if (length > 0 && distance + length >= target) {
        final f = ((target - distance) / length).clamp(0.0, 1.0);
        probes.add(
          Coordinates(
            latitude:
                points[i].latitude +
                (points[i + 1].latitude - points[i].latitude) * f,
            longitude:
                points[i].longitude +
                (points[i + 1].longitude - points[i].longitude) * f,
          ),
        );
        break;
      }
      distance += length;
    }
  }
  double score(CityWalkingRoute candidate) {
    final p = candidate.geometry.points;
    var hits = 0;
    for (final probe in probes) {
      var nearest = double.infinity;
      for (var i = 1; i < p.length; i++) {
        nearest = math.min(
          nearest,
          projectToWalk(probe, p[i - 1], p[i]).distance,
        );
        if (nearest <= 25) break;
      }
      if (nearest <= 25) hits++;
    }
    return hits / probes.length;
  }

  int? best;
  var bestScore = .60;
  for (var i = 0; i < candidates.length; i++) {
    final s = score(candidates[i]);
    if (s > bestScore ||
        (s == bestScore &&
            best != null &&
            candidates[i].geometry.durationSeconds <
                candidates[best].geometry.durationSeconds)) {
      best = i;
      bestScore = s;
    }
  }
  return best;
}
