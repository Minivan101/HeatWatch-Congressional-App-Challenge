import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

import 'pedestrian_navigation_test.dart' show network;

void main() {
  final snapshot = jsonDecode(
    File('docs/research/vegas-long-foot-route-2026-10-10.json')
        .readAsStringSync(),
  );
  final first = snapshot['routes'][0]['geometry']['coordinates'];
  final start = Coordinates(latitude: first[0][1], longitude: first[0][0]);
  final end = Coordinates(latitude: first[20][1], longitude: first[20][0]);

  final coords = first.take(21).toList();
  final copied = jsonDecode(jsonEncode(snapshot));
  final r = copied['routes'][0];
  r['geometry']['coordinates'] = coords;

  var distance = 0.0;
  for (var i = 1; i < coords.length; i++) {
    distance += distanceBetween(coords[i - 1], coords[i]);
  }
  r['distance'] = distance;
  r['duration'] = distance / 1.25;
  r['legs'] = [
    {
      'steps': [
        {
          'mode': 'walking',
          'name': 'Public mapped path',
          'distance': distance,
          'maneuver': {'type': 'depart'},
        },
        {
          'mode': 'walking',
          'distance': 0,
          'maneuver': {'type': 'arrive'},
        },
      ],
    },
  ];
  copied['routes'] = [r];
  copied['waypoints'] = [
    {'distance': 0},
    {'distance': 0},
  ];
  for (final mode in ['outage', 'partial', 'malformed']) {
    test('$mode map transfer recovers through genuine foot service', () async {
      final methods = <String>[];
      final service = PedestrianTripService(
        client: MockClient((req) async {
          methods.add(req.method);
          if (req.method == 'POST') {
            return http.Response(
              mode == 'partial'
                  ? jsonEncode({'remark': 'timeout', 'elements': []})
                  : mode == 'malformed'
                  ? jsonEncode({'error': 'invalid envelope'})
                  : 'unavailable',
              mode == 'outage' ? 503 : 200,
            );
          }
          expect(req.url.path, contains('/routed-foot/'));
          return http.Response(jsonEncode(copied), 200);
        }),
      );
      addTearDown(service.client.close);
      final result = await service.walkAlternatives(start, end);
      expect(
        result.single.geometry.sourceUrl,
        contains('routing.openstreetmap.de'),
      );
      expect(methods, ['POST', 'GET']);
    });
  }
  test('access rejection on a complete map never falls through to another provider', () async {
    var requests = 0;
    final data = network(tags: {'highway': 'footway', 'foot': 'no'});
    (data['elements'] as List).removeLast();
    final service = PedestrianTripService(
      client: MockClient((req) async {
        requests++;
        expect(req.method, 'POST');
        return http.Response(jsonEncode(data), 200);
      }),
    );
    addTearDown(service.client.close);
    expect(
      () => service.walkAlternatives(
        const Coordinates(latitude: 36.19, longitude: -115.28),
        const Coordinates(latitude: 36.19, longitude: -115.278),
      ),
      throwsFormatException,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, 1);
  });
  test(
    'both services failing return an error, never a fabricated line',
    () async {
      final service = PedestrianTripService(
        client: MockClient((_) async => http.Response('down', 503)),
      );
      addTearDown(service.client.close);
      await expectLater(
        service.walkAlternatives(start, end),
        throwsFormatException,
      );
    },
  );
}

double distanceBetween(dynamic a, dynamic b) => walkingDistance(
  Coordinates(latitude: a[1], longitude: a[0]),
  Coordinates(latitude: b[1], longitude: b[0]),
);
