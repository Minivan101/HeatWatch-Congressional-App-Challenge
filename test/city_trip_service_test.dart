import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

Map<String, dynamic> route() => {
  'code': 'Ok',
  'routes': [
    {
      'duration': 400,
      'distance': 143,
      'legs': [
        {
          'steps': [
            {
              'mode': 'walking',
              'distance': 143,
              'maneuver': {'type': 'depart'},
              'name': 'Test path',
            },
            {
              'mode': 'walking',
              'distance': 0,
              'maneuver': {'type': 'arrive'},
            },
          ],
        },
      ],
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [-115.28, 36.19],
          [-115.281, 36.191],
        ],
      },
    },
  ],
  'waypoints': [
    {'distance': 2},
  ],
};

void main() {
  test('multi-leg timings join at the waypoint and partial annotations are rejected', () {
    final data = jsonDecode(jsonEncode(route())) as Map<String, dynamic>;
    final r = data['routes'][0];
    r['geometry']['coordinates'].insert(1, [-115.2805, 36.1905]);
    r['legs'] = [
      {
        'annotation': {
          'duration': [180.0],
        },
        'steps': [
          {
            'mode': 'walking',
            'distance': 71.5,
            'maneuver': {'type': 'depart'},
          },
        ],
      },
      {
        'annotation': {
          'duration': [218.0],
        },
        'steps': [
          {
            'mode': 'walking',
            'distance': 71.5,
            'maneuver': {'type': 'turn'},
          },
          {
            'mode': 'walking',
            'distance': 0.0,
            'maneuver': {'type': 'arrive'},
          },
        ],
      },
    ];
    expect(CityTripService.parseRoute(data).geometry.segmentSeconds, [
      180.0,
      218.0,
    ]);
    r['legs'][1].remove('annotation');
    expect(() => CityTripService.parseRoute(data), throwsFormatException);
  });

  test(
    'provider timing annotations are retained and malformed timing is rejected',
    () {
      final data = jsonDecode(jsonEncode(route())) as Map<String, dynamic>;
      final leg = data['routes'][0]['legs'][0];
      leg['annotation'] = {
        'duration': [398.0],
      };
      expect(CityTripService.parseRoute(data).geometry.segmentSeconds, [398.0]);
      for (final bad in [
        <double>[],
        [double.nan],
        [-1.0],
        [1.0],
        [200.0, 200.0],
      ]) {
        leg['annotation'] = {'duration': bad};
        expect(() => CityTripService.parseRoute(data), throwsFormatException);
      }
    },
  );
  test('inconsistent distance, collapsed geometry and missing instructions cannot enter navigation', () {
    for (final mutation in ['distance', 'collapsed', 'legs', 'arrival']) {
      final data = route();
      final r = data['routes'][0];
      if (mutation == 'distance') r['distance'] = 1000;
      if (mutation == 'collapsed') {
        r['geometry']['coordinates'][1] = r['geometry']['coordinates'][0];
      }
      if (mutation == 'legs') r.remove('legs');
      if (mutation == 'arrival') r['legs'][0]['steps'].removeLast();
      expect(
        () => CityTripService.parseRoute(data),
        throwsFormatException,
        reason: mutation,
      );
    }
  });
  test('walking route requires valid geometry, finite walking metrics and close snapping', () {
    expect(CityTripService.parseRoute(route()).geometry.points.length, 2);
    var data = route();
    data['routes'][0]['duration'] = 0;
    expect(() => CityTripService.parseRoute(data), throwsFormatException);
    data = route();
    data['waypoints'][0]['distance'] = 200;
    expect(() => CityTripService.parseRoute(data), throwsFormatException);
    data = route();
    data['routes'][0]['geometry']['type'] = 'Polygon';
    expect(() => CityTripService.parseRoute(data), throwsFormatException);
  });
  test('explicit search is bounded, identified, cached and validates place coordinates', () async {
    var requests = 0;
    final service = CityTripService(
      client: MockClient((request) async {
        requests++;
        expect(request.url.host, 'photon.komoot.io');
        expect(request.headers['User-Agent'], contains('HeatWatch'));
        expect(request.url.queryParameters['bbox'], isNotNull);
        expect(request.url.queryParameters['limit'], '20');
        expect(request.url.queryParameters['dedupe'], '0');
        expect(request.url.queryParameters['lat'], '36.1699');
        expect(request.url.queryParameters['lon'], '-115.1398');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'type': 'Point',
                  'coordinates': [-115.28, 36.19],
                },
                'properties': {'name': 'Public park', 'city': 'Las Vegas'},
              },
              {
                'geometry': {
                  'type': 'Point',
                  'coordinates': [0, 0],
                },
                'properties': {'name': 'Elsewhere'},
              },
            ],
          }),
          200,
        );
      }),
    );
    expect((await service.search('Public park')).length, 1);
    expect((await service.search('public park')).first.name, 'Public park');
    expect(requests, 1);
  });
  test('an exact named place outranks loosely related venues', () async {
    final service = CityTripService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'type': 'Point',
                  'coordinates': [-115.20, 36.19],
                },
                'properties': {'name': 'Las Vegas North Premium Outlets'},
              },
              {
                'geometry': {
                  'type': 'Point',
                  'coordinates': [-115.18, 36.10],
                },
                'properties': {'name': 'Las Vegas South Premium Outlets'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    final places = await service.search('South Premium Outlets');
    expect(places.first.name, 'Las Vegas South Premium Outlets');
    service.client.close();
  });
  test('route uses foot server and repeated route is cached', () async {
    var requests = 0;
    final service = CityTripService(
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, contains('/routed-foot/route/v1/foot/'));
        expect(request.url.queryParameters['alternatives'], '3');
        expect(request.url.queryParameters['annotations'], 'duration');
        return http.Response(jsonEncode(route()), 200);
      }),
    );
    const a = Coordinates(latitude: 36.19, longitude: -115.28),
        b = Coordinates(latitude: 36.191, longitude: -115.281);
    expect((await service.walk(a, b)).distanceMeters, 143);
    await service.walk(a, b);
    expect(requests, 1);
  });
  test('alternatives are distinct valid paths with the same endpoints; never invented', () {
    final data = route();
    final primary = data['routes'][0];
    final alternative = jsonDecode(jsonEncode(primary));
    alternative['geometry']['coordinates'].insert(1, [-115.282, 36.1905]);
    alternative['duration'] = 450;
    final coords = alternative['geometry']['coordinates'] as List;
    var meters = 0.0;
    for (var i = 1; i < coords.length; i++) {
      meters += walkingDistance(
        Coordinates(latitude: coords[i - 1][1], longitude: coords[i - 1][0]),
        Coordinates(latitude: coords[i][1], longitude: coords[i][0]),
      );
    }
    alternative['distance'] = meters;
    alternative['legs'][0]['steps'][0]['distance'] = meters;
    final invalid = jsonDecode(jsonEncode(alternative));
    invalid['duration'] = -1;
    final wrongEndpoint = jsonDecode(jsonEncode(alternative));
    wrongEndpoint['geometry']['coordinates'][0] = [-115.30, 36.20];
    data['routes'] = [primary, primary, invalid, wrongEndpoint, alternative];
    final paths = CityTripService.parseAlternatives(data);
    expect(paths.length, 2);
    expect(paths.last.geometry.durationSeconds, 450);
    expect(CityTripService.parseAlternatives(route()).length, 1);
    expect(
      () => CityTripService.parseAlternatives({'code': 'NoRoute'}),
      throwsFormatException,
    );
  });
  test('every alternative stays near requested endpoints, not only snapped primary', () async {
    const a = Coordinates(latitude: 36.19, longitude: -115.28),
        b = Coordinates(latitude: 36.191, longitude: -115.281);
    final data = route();
    final primary = data['routes'][0];

    primary['geometry']['coordinates'][0] = [-115.28, 36.191];
    primary['distance'] = 89.8;
    primary['legs'][0]['steps'][0]['distance'] = 89.8;
    final alternative = jsonDecode(jsonEncode(primary));
    alternative['geometry']['coordinates'][0] = [-115.28, 36.192];
    alternative['distance'] = 143;
    alternative['legs'][0]['steps'][0]['distance'] = 143;
    data['routes'] = [primary, alternative];
    final service = CityTripService(
      client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
    );
    addTearDown(service.client.close);
    expect(CityTripService.parseAlternatives(data), hasLength(2));
    final matched = await service.walkAlternatives(a, b);
    expect(matched, hasLength(1));
    expect(matched.first.geometry.points.first.latitude, 36.191);
    expect(await service.walkAlternatives(a, b), same(matched));
  });
}
