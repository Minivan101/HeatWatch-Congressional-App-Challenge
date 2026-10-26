import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';

const a = Coordinates(latitude: 36.17, longitude: -115.14);
const b = Coordinates(latitude: 36.171, longitude: -115.14);
const c = Coordinates(latitude: 36.17, longitude: -115.139);
CityWalkingRoute trip(List<Coordinates> points) => CityWalkingRoute(
  WalkingGeometry(
    points: points,
    durationSeconds: 250,
    sourceUrl: 'test-only',
    accessReviewed: false,
  ),
  [
    for (var i = 0; i < points.length - 1; i++)
      walkingDistance(points[i], points[i + 1]),
  ].reduce((x, y) => x + y),
);
void main() {
  test(
    'outbound then return overlap uses direction and continuous progress',
    () {
      final route = trip([a, b, a, c]);
      final tracker = WalkingRouteTracker();
      expect(tracker.update(route, a).arrived, false);
      final middle = Coordinates(latitude: 36.1705, longitude: -115.14);
      expect(tracker.update(route, middle).alongMeters, closeTo(55.66, .1));
      expect(tracker.update(route, b).alongMeters, closeTo(111.32, .1));
      final returning = tracker.update(route, middle);
      expect(returning.alongMeters, closeTo(166.98, .1));
      expect(returning.bearing, closeTo(180, .1));
      expect(
        returning.remainingMeters,
        closeTo(route.distanceMeters - 166.98, .1),
      );
      expect(tracker.update(route, a).alongMeters, closeTo(222.64, .1));
      expect(tracker.update(route, c).arrived, true);
    },
  );
  test('return-to-origin arrival is not mistaken for arrival at departure', () {
    final route = trip([a, b, a]);
    final t = WalkingRouteTracker();
    expect(t.update(route, a).arrived, false);
    t.update(route, b);
    t.update(route, const Coordinates(latitude: 36.1705, longitude: -115.14));
    expect(t.update(route, a).arrived, true);
  });
  test('genuine backwards walking on a single leg can decrease progress', () {
    final route = trip([a, b]);
    final t = WalkingRouteTracker();
    t.update(route, a);
    final forward = t.update(
      route,
      const Coordinates(latitude: 36.1707, longitude: -115.14),
    );
    final backward = t.update(
      route,
      const Coordinates(latitude: 36.1704, longitude: -115.14),
    );
    expect(backward.alongMeters, lessThan(forward.alongMeters));
    expect(backward.arrived, false);
  });
  test('switching or rerouting resets continuity to the new geometry', () {
    final t = WalkingRouteTracker();
    final first = trip([a, b, a, c]);
    t.update(first, a);
    t.update(first, b);
    final second = trip([b, c]);
    expect(t.update(second, b).alongMeters, closeTo(0, .01));
    t.reset();
    expect(t.update(first, a).alongMeters, closeTo(0, .01));
  });
  test('nearer isolated sidewalk cannot hide nearby connected mapped path', () {
    final data = <String, dynamic>{
      'elements': [
        {'type': 'node', 'id': 1, 'lat': 36.17, 'lon': -115.14},
        {'type': 'node', 'id': 2, 'lat': 36.1701, 'lon': -115.14},
        {'type': 'node', 'id': 3, 'lat': 36.17, 'lon': -115.1401},
        {'type': 'node', 'id': 4, 'lat': 36.171, 'lon': -115.1401},
        {
          'type': 'way',
          'id': 10,
          'nodes': [1, 2],
          'tags': {'highway': 'footway'},
        },
        {
          'type': 'way',
          'id': 11,
          'nodes': [3, 4],
          'tags': {'highway': 'footway', 'footway': 'sidewalk'},
        },
      ],
    };
    final routes = PedestrianGraph(data).routes([a, b]);
    expect(routes, isNotEmpty);
    expect(
      routes.first.geometry.points.every(
        (p) => (p.longitude + 115.1401).abs() < 1e-7,
      ),
      true,
    );
    expect(routes.first.distanceMeters, closeTo(111.32, .1));
  });
}
