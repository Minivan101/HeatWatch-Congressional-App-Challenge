import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/shade_route_service.dart';

void main() {
  test('trip serializes the guide contract with a zoned time', () {
    final trip = ShadeRouteTrip(
      origin: const Coordinates(latitude: 34.00003, longitude: -118.00078),
      destination: const Coordinates(latitude: 34.00003, longitude: -117.9994),
      departureTime: DateTime.utc(2026, 6, 21, 16),
    );
    expect(trip.toCallableData(), {
      'origin': {'lat': 34.00003, 'lng': -118.00078},
      'destination': {'lat': 34.00003, 'lng': -117.9994},
      'departureTime': '2026-06-21T16:00:00.000Z',
    });
  });

  test('invalid trip cannot be sent to Functions', () {
    final trip = ShadeRouteTrip(
      origin: const Coordinates(latitude: 91, longitude: 0),
      destination: const Coordinates(latitude: 34, longitude: -118),
      departureTime: DateTime.utc(2026, 6, 21),
    );
    expect(trip.toCallableData, throwsFormatException);
  });
}
