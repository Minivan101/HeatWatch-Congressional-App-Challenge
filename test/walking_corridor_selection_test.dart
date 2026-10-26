import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/walking_corridor_selection.dart';

const a = Coordinates(latitude: 36.19, longitude: -115.28),
    b = Coordinates(latitude: 36.19, longitude: -115.27),
    c = Coordinates(latitude: 36.20, longitude: -115.27),
    d = Coordinates(latitude: 36.20, longitude: -115.28);
CityWalkingRoute path(List<Coordinates> p) => CityWalkingRoute(
  WalkingGeometry(
    points: p,
    durationSeconds: 1000,
    sourceUrl: 'https://example.com/test-only',
    accessReviewed: false,
  ),
  2000,
);
void main() {
  test('retain a selected corridor from remaining geometry rather than old candidate index', () {
    final old = path([a, b, c]);
    expect(
      matchingWalkingCorridor(
        [
          path([a, d, c]),
          path([b, c]),
        ],
        old,
        900,
      ),
      1,
    );
  });
  test('no matching corridor defers to preference instead of inventing a connection', () {
    expect(
      matchingWalkingCorridor(
        [
          path([a, d]),
        ],
        path([a, b, c]),
        0,
      ),
      null,
    );
  });
}
