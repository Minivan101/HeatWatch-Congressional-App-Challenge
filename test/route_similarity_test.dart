import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/route_similarity.dart';

Coordinates point(double x, double y) => Coordinates(
  latitude: 36.17 + y / 111320,
  longitude: -115.14 + x / (111320 * .80727),
);
CityWalkingRoute route(List<(double, double)> points) => CityWalkingRoute(
  WalkingGeometry(
    points: [for (final p in points) point(p.$1, p.$2)],
    durationSeconds: 600,
    sourceUrl: 'test fixture',
    accessReviewed: false,
  ),
  1000,
);
void main() {
  test('same path with dense versus sparse geometry combines', () {
    final sparse = route([(0, 0), (1000, 0)]);
    final dense = route([for (var i = 0; i <= 100; i++) (i * 10.0, 0)]);
    expect(routesMostlyOverlap(sparse, dense), true);
  });
  test('shared stem and a short distinct spur combine', () {
    final main = route([(0, 0), (1000, 0)]);
    final spur = route([(0, 0), (450, 0), (475, 25), (500, 0), (1000, 0)]);
    expect(routesMostlyOverlap(main, spur), true);
  });
  test('overlap above 85 percent but below 90 percent stays separate', () {
    final main = route([(0, 0), (1000, 0)]);
    final detour = route([(0, 0), (900, 0), (900, 20), (1000, 20), (1000, 0)]);
    expect(routesMostlyOverlap(main, detour), false);
    expect(routesMostlyOverlap(detour, main), false);
  });
  test('overlap above 90 percent still combines', () {
    final main = route([(0, 0), (1000, 0)]);
    final detour = route([(0, 0), (950, 0), (950, 20), (1000, 20), (1000, 0)]);
    expect(routesMostlyOverlap(main, detour), true);
    expect(routesMostlyOverlap(detour, main), true);
  });
  test('routes with a substantial different corridor stay separate', () {
    final main = route([(0, 0), (1000, 0)]);
    final detour = route([
      (0, 0),
      (300, 0),
      (400, 100),
      (600, 100),
      (700, 0),
      (1000, 0),
    ]);
    expect(routesMostlyOverlap(main, detour), false);
  });
  test('overlap must cover both routes rather than only the shorter route', () {
    final short = route([(0, 0), (300, 0)]);
    final long = route([(0, 0), (1000, 0)]);
    expect(routesMostlyOverlap(short, long), false);
    expect(routesMostlyOverlap(long, short), false);
  });
  test(
    'small map offsets combine; separate parallel sidewalks stay distinct',
    () {
      final main = route([(0, 0), (1000, 0)]);
      expect(routesMostlyOverlap(main, route([(0, 8), (1000, 8)])), true);
      expect(routesMostlyOverlap(main, route([(0, 20), (1000, 20)])), false);
    },
  );
  test('many shared vertices cannot hide a long different section', () {
    final straight = route([(0, 0), (1000, 0)]);
    final misleading = route([
      for (var i = 0; i < 100; i++) (i * 1.0, 0),
      (500, 300),
      (1000, 0),
    ]);
    expect(routesMostlyOverlap(straight, misleading), false);
  });
  test('a long-route difference is not lost to sparse route sampling', () {
    final main = route([(0, 0), (50000, 0)]);
    final same = route([(0, 0), (25000, 0), (50000, 0)]);
    final different = route([
      (0, 0),
      (10000, 0),
      (20000, 5000),
      (40000, 5000),
      (50000, 0),
    ]);
    expect(routesMostlyOverlap(main, same), true);
    expect(routesMostlyOverlap(main, different), false);
  });
}
