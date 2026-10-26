import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

const a = Coordinates(latitude: 36.19, longitude: -115.28);
const b = Coordinates(latitude: 36.19, longitude: -115.27);
const c = Coordinates(latitude: 36.20, longitude: -115.27);
CityWalkingRoute route(List<Coordinates> points) => CityWalkingRoute(
  WalkingGeometry(
    points: points,
    durationSeconds: 1000,
    sourceUrl: 'https://example.com/test-only',
    accessReviewed: false,
  ),
  2000,
);
void main() {
  test(
    'ordered intermediate points distinguish outbound and returning visits',
    () {
      final offsets = walkingWaypointOffsets(route([a, b, c, b, a, b]), [
        c,
        a,
        b,
      ]);
      expect(offsets[0], greaterThan(1900));
      expect(offsets[1], greaterThan(offsets[0]));
      expect(offsets[2], greaterThan(offsets[1]));
    },
  );
  test('reject missing or out-of-order intermediate points rather than invent connectors', () {
    expect(
      () => walkingWaypointOffsets(route([a, b, c]), [c, a]),
      throwsFormatException,
    );
    expect(
      () => walkingWaypointOffsets(route([a, b]), [c]),
      throwsFormatException,
    );
  });
}
