import 'dart:math' as math;

import '../../../core/models/coordinates.dart';
import 'city_trip_service.dart';

double walkingDistance(Coordinates a, Coordinates b) {
  final dy = (b.latitude - a.latitude) * 111320;
  final dx =
      (b.longitude - a.longitude) *
      111320 *
      math.cos((a.latitude + b.latitude) * math.pi / 360);
  return math.sqrt(dx * dx + dy * dy);
}

double walkingBearing(Coordinates a, Coordinates b) =>
    (math.atan2(
              (b.longitude - a.longitude) *
                  math.cos((a.latitude + b.latitude) * math.pi / 360),
              b.latitude - a.latitude,
            ) *
            180 /
            math.pi +
        360) %
    360;

({Coordinates point, double fraction, double distance}) projectToWalk(
  Coordinates p,
  Coordinates a,
  Coordinates b,
) {
  final scale = math.cos(a.latitude * math.pi / 180);
  final dx = (b.longitude - a.longitude) * scale;
  final dy = b.latitude - a.latitude;
  final x = (p.longitude - a.longitude) * scale;
  final y = p.latitude - a.latitude;
  final length = dx * dx + dy * dy;
  final t = length == 0 ? 0.0 : ((x * dx + y * dy) / length).clamp(0.0, 1.0);
  final q = Coordinates(
    latitude: a.latitude + dy * t,
    longitude: a.longitude + (b.longitude - a.longitude) * t,
  );
  return (point: q, fraction: t, distance: walkingDistance(p, q));
}

class WalkingProgress {
  const WalkingProgress(
    this.alongMeters,
    this.remainingMeters,
    this.offRouteMeters,
    this.bearing,
    this.instruction,
  );
  final double alongMeters, remainingMeters, offRouteMeters, bearing;
  final String instruction;
  bool get arrived => remainingMeters < 12 && offRouteMeters < 20;
}

class WalkingRouteTracker {
  CityWalkingRoute? _route;
  Coordinates? _previousPoint;
  double? _along;
  void reset() {
    _route = null;
    _previousPoint = null;
    _along = null;
  }

  WalkingProgress update(CityWalkingRoute route, Coordinates point) {
    if (!identical(route, _route)) reset();
    final moved = _previousPoint == null
        ? null
        : walkingDistance(_previousPoint!, point);
    final result = walkingProgress(
      route,
      point,
      previousAlong: _along,
      movementBearing: moved != null && moved >= 3
          ? walkingBearing(_previousPoint!, point)
          : null,
      movedMeters: moved,
    );
    _route = route;

    if (result.offRouteMeters <= 35) {
      _previousPoint = point;
      _along = result.alongMeters;
    }
    return result;
  }
}

WalkingProgress walkingProgress(
  CityWalkingRoute route,
  Coordinates p, {
  double? previousAlong,
  double? movementBearing,
  double? movedMeters,
}) {
  final points = route.geometry.points;
  double total = 0, along = 0, nearest = double.infinity, offset = 0;
  var segment = 0;
  final candidates =
      <
        ({
          int segment,
          double distance,
          double along,
          double offset,
          double bearing,
        })
      >[];
  for (var i = 0; i < points.length - 1; i++) {
    final length = walkingDistance(points[i], points[i + 1]);
    final projection = projectToWalk(p, points[i], points[i + 1]);
    candidates.add((
      segment: i,
      distance: projection.distance,
      along: total + length * projection.fraction,
      offset: length * (1 - projection.fraction),
      bearing: walkingBearing(points[i], points[i + 1]),
    ));
    nearest = math.min(nearest, projection.distance);
    total += length;
  }
  if (candidates.isEmpty) {
    throw const FormatException('Walking route needs at least two points.');
  }

  final close = candidates.where((c) => c.distance <= nearest + 8).toList();
  final budget = math.max(30.0, (movedMeters ?? 0) * 2 + 15);
  final continuous = previousAlong == null
      ? close
      : close.where((c) => (c.along - previousAlong).abs() <= budget).toList();
  final choices = continuous.isEmpty ? close : continuous;
  double score(
    ({
      int segment,
      double distance,
      double along,
      double offset,
      double bearing,
    })
    c,
  ) {
    if (previousAlong == null) return c.distance + c.along * 1e-8;
    final turn = movementBearing == null
        ? 0.0
        : ((c.bearing - movementBearing + 540) % 360 - 180).abs();
    return c.distance + (c.along - previousAlong).abs() * .15 + turn / 180 * 12;
  }

  final match = choices.reduce((a, b) => score(b) < score(a) ? b : a);
  along = match.along;
  segment = match.segment;
  offset = match.offset;

  nearest = match.distance;
  String instruction = 'Continue on the walking path';
  for (final step in route.steps) {
    if (step.atMeters + 8 >= along) {
      final meters = math.max(0, step.atMeters - along).round();
      instruction = meters > 15
          ? 'In $meters m, ${step.instruction}'
          : step.instruction;
      break;
    }
  }
  if (route.steps.isEmpty && segment + 2 < points.length) {
    final first = walkingBearing(points[segment], points[segment + 1]);
    final next = walkingBearing(points[segment + 1], points[segment + 2]);
    final turn = (next - first + 540) % 360 - 180;
    if (turn.abs() >= 30) {
      instruction =
          'In ${offset.round()} m, turn ${turn > 0 ? 'right' : 'left'}';
    }
  }
  if (total - along < 12 && nearest < 20) instruction = 'You have arrived';
  return WalkingProgress(
    along,
    math.max(0, total - along),
    nearest,
    walkingBearing(points[segment], points[segment + 1]),
    instruction,
  );
}

List<double> walkingWaypointOffsets(
  CityWalkingRoute route,
  List<Coordinates> waypoints,
) {
  final offsets = <double>[];
  var minimum = 0.0;
  for (final waypoint in waypoints) {
    var cumulative = 0.0, bestDistance = double.infinity;
    double? bestAlong;
    final points = route.geometry.points;
    for (var i = 0; i < points.length - 1; i++) {
      final length = walkingDistance(points[i], points[i + 1]);
      final projection = projectToWalk(waypoint, points[i], points[i + 1]);
      final along = cumulative + length * projection.fraction;
      if (along + .1 >= minimum && projection.distance < bestDistance - .01) {
        bestDistance = projection.distance;
        bestAlong = along;
      }
      cumulative += length;
    }
    if (bestAlong == null || bestDistance > 150) {
      throw const FormatException(
        'Walking route misses an intermediate point.',
      );
    }
    offsets.add(bestAlong);
    minimum = bestAlong;
  }
  return offsets;
}
