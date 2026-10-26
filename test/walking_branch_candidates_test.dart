import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';

Map<String, dynamic> stem({bool restricted = false, bool oneWay = false}) => {
  'elements': [
    {'type': 'node', 'id': 1, 'lat': 36.19, 'lon': -115.28},
    {'type': 'node', 'id': 2, 'lat': 36.20, 'lon': -115.28},
    {'type': 'node', 'id': 3, 'lat': 36.20009, 'lon': -115.28},
    {'type': 'node', 'id': 4, 'lat': 36.20005, 'lon': -115.2802},
    {
      'type': 'way',
      'id': 10,
      'nodes': [1, 2, 3],
      'tags': {'highway': 'footway'},
    },
    {
      'type': 'way',
      'id': 11,
      'nodes': [2, 4, 3],
      'tags': {
        'highway': 'footway',
        if (restricted) 'foot': 'no',
        if (oneWay) 'oneway:foot': '-1',
      },
    },
  ],
};
const start = Coordinates(latitude: 36.19, longitude: -115.28);
const end = Coordinates(latitude: 36.20009, longitude: -115.28);
void main() {
  test('a shared stem must not hide a genuine small branch alternative', () {
    final routes = PedestrianGraph(stem()).routes([start, end]);
    expect(routes, hasLength(2));
    expect(
      routes.last.distanceMeters,
      lessThan(routes.first.distanceMeters * 1.1),
    );
    expect(
      routes.last.geometry.points.toSet().length,
      routes.last.geometry.points.length,
    );
  });
  test('branch discovery preserves foot exclusions and direction', () {
    expect(
      PedestrianGraph(stem(restricted: true)).routes([start, end]),
      hasLength(1),
    );
    expect(
      PedestrianGraph(stem(oneWay: true)).routes([start, end]),
      hasLength(1),
    );
  });
}
