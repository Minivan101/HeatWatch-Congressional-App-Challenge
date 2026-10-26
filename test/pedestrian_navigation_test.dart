import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

const a = Coordinates(latitude: 36.19, longitude: -115.28);
const b = Coordinates(latitude: 36.19, longitude: -115.278);
Map<String, dynamic> network({
  Map<String, String> tags = const {
    'highway': 'footway',
    'footway': 'sidewalk',
  },
}) => {
  'elements': <Map<String, dynamic>>[
    for (var i = 1; i <= 3; i++)
      {'type': 'node', 'id': i, 'lat': 36.19, 'lon': -115.281 + i * .001},
    {'type': 'node', 'id': 4, 'lat': 36.191, 'lon': -115.279},
    {
      'type': 'way',
      'id': 10,
      'nodes': [1, 2, 3],
      'tags': Map<String, String>.of(tags),
    },
    {
      'type': 'way',
      'id': 11,
      'nodes': [1, 4, 3],
      'tags': {'highway': 'path'},
    },
  ],
};

class LiveLocation extends LocationService {
  final updates = StreamController<WalkingLocationFix>.broadcast(sync: true);
  int prompts = 0, subscriptions = 0;
  @override
  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async {
    if (requestPermission) prompts++;
    return a;
  }

  @override
  Stream<WalkingLocationFix> watchPosition() {
    subscriptions++;
    return updates.stream;
  }
}

void main() {
  test(
    'cropped connectivity retries wider once and then caches the larger graph',
    () async {
      var requests = 0;
      var now = DateTime.utc(2026, 10, 11);
      final boxes = <String>[];
      final wide = network();
      wide['elements'][3]['lat'] = 36.20;
      const far = Coordinates(latitude: 36.20, longitude: -115.279);
      final cropped = jsonDecode(jsonEncode(wide)) as Map<String, dynamic>;
      cropped['elements'][4]['nodes'] = [1, 2];
      cropped['elements'][5]['nodes'] = [3, 4];
      final service = PedestrianTripService(
        now: () => now,
        client: MockClient((request) async {
          requests++;
          boxes.add(Uri.splitQueryString(request.body)['data']!);
          now = now.add(const Duration(seconds: 10));
          return http.Response(jsonEncode(requests == 1 ? cropped : wide), 200);
        }),
      );
      addTearDown(service.client.close);
      expect(await service.walkAlternatives(a, far), isNotEmpty);
      expect(requests, 2);
      expect(boxes[1], isNot(boxes[0]));
      expect(await service.walkAlternatives(a, far), isNotEmpty);
      expect(requests, 2);
    },
  );
  test(
    'map connectivity expansion never bypasses explicit foot denial',
    () async {
      var maps = 0, foot = 0;
      final denied = network(tags: {'highway': 'footway', 'foot': 'no'});
      denied['elements'].removeLast();
      final service = PedestrianTripService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            maps++;
            return http.Response(jsonEncode(denied), 200);
          }
          foot++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(service.client.close);
      await expectLater(service.walkAlternatives(a, b), throwsFormatException);
      expect(maps, 1);
      expect(foot, 0);
    },
  );

  test('disconnected public map asks foot router before reporting an entrance issue', () async {
    final disconnected = network();
    disconnected['elements'][4]['nodes'] = [1, 2];
    disconnected['elements'][5]['nodes'] = [3, 4];
    disconnected['elements'][2]['lon'] = -115.273;
    disconnected['elements'][3]['lon'] = -115.273;
    const farEntrance = Coordinates(latitude: 36.19, longitude: -115.273);
    var maps = 0, foot = 0;
    var now = DateTime.utc(2026, 10, 11);
    final service = PedestrianTripService(
      now: () => now,
      client: MockClient((request) async {
        now = now.add(const Duration(seconds: 10));
        if (request.method == 'POST') {
          maps++;
          return http.Response(jsonEncode(disconnected), 200);
        }
        foot++;
        return http.Response('unavailable', 503);
      }),
    );
    addTearDown(service.client.close);
    await expectLater(
      service.walkAlternatives(a, farEntrance),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('accessible entrance'),
        ),
      ),
    );
    expect(maps, 2);
    expect(foot, 1);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pedestrian graph uses connected real ways and returns distinct candidates',
    () {
      final routes = PedestrianGraph(network()).routes([a, b]);
      expect(routes, hasLength(2));
      expect(routes.first.geometry.points.length, 3);
      expect(routes.first.steps.first.instruction, contains('sidewalk'));
      expect(
        routes.last.distanceMeters,
        greaterThan(routes.first.distanceMeters),
      );
      expect(routes.first.distanceMeters, closeTo(179.7, 2));
    },
  );
  for (final tags in [
    {'highway': 'residential', 'sidewalk': 'both'},
    {'highway': 'motorway', 'foot': 'yes'},
    {'highway': 'footway', 'foot': 'no'},
    {'highway': 'footway', 'access': 'private'},
    {'highway': 'footway', 'access:conditional': 'yes @ (Mo-Fr)'},
    {'highway': 'cycleway'},
    {'highway': 'footway', 'construction': 'yes'},
  ]) {
    test('excludes restricted or nonpedestrian way: $tags', () {
      final data = network(tags: tags);
      (data['elements'] as List).removeLast();
      expect(() => PedestrianGraph(data).routes([a, b]), throwsFormatException);
    });
  }
  test('does not fabricate connection between nearby disconnected ways', () {
    final data = network();
    (data['elements'] as List).removeLast();
    (data['elements'] as List).removeWhere((e) => e['type'] == 'way');
    (data['elements'] as List).addAll(<Map<String, dynamic>>[
      {
        'type': 'way',
        'id': 10,
        'nodes': [1, 2],
        'tags': {'highway': 'footway'},
      },
      {'type': 'node', 'id': 5, 'lat': 36.19001, 'lon': -115.279},
      {
        'type': 'way',
        'id': 11,
        'nodes': [5, 3],
        'tags': {'highway': 'footway'},
      },
    ]);
    expect(() => PedestrianGraph(data).routes([a, b]), throwsFormatException);
  });
  test('snaps to actual segment preserving walking one-way', () {
    final data = network(tags: {'highway': 'footway', 'oneway:foot': 'yes'});
    (data['elements'] as List).removeLast();
    const middle = Coordinates(latitude: 36.19, longitude: -115.2795);
    expect(
      PedestrianGraph(data)
          .routes([middle, b])
          .first
          .geometry
          .points
          .first
          .longitude,
      closeTo(-115.2795, 1e-8),
    );
    expect(
      () => PedestrianGraph(data).routes([b, middle]),
      throwsFormatException,
    );
  });
  test('node access and locked barriers block paths', () {
    final data = network();
    (data['elements'] as List).removeLast();
    data['elements'][1]['tags'] = {'barrier': 'gate', 'locked': 'yes'};
    expect(() => PedestrianGraph(data).routes([a, b]), throwsFormatException);
  });
  test('requires mapped crossing at same-level vehicle-road intersection', () {
    final data = network();
    (data['elements'] as List).removeLast();
    (data['elements'] as List).addAll(<Map<String, dynamic>>[
      {'type': 'node', 'id': 20, 'lat': 36.189, 'lon': -115.2795},
      {'type': 'node', 'id': 21, 'lat': 36.191, 'lon': -115.2795},
      {
        'type': 'way',
        'id': 22,
        'nodes': [20, 21],
        'tags': {'highway': 'residential'},
      },
    ]);
    expect(() => PedestrianGraph(data).routes([a, b]), throwsFormatException);
    data['elements'].firstWhere((e) => e['id'] == 10)['tags']['footway'] =
        'crossing';
    expect(PedestrianGraph(data).routes([a, b]), isNotEmpty);
  });
  test(
    'walking progress gives local heading, remaining distance and arrival',
    () {
      final route = PedestrianGraph(network()).routes([a, b]).first;
      const middle = Coordinates(latitude: 36.19, longitude: -115.279);
      final progress = walkingProgress(route, middle);
      expect(progress.bearing, closeTo(90, .1));
      expect(progress.remainingMeters, closeTo(route.distanceMeters / 2, 1));
      expect(progress.offRouteMeters, 0);
      expect(progress.arrived, false);
      expect(walkingProgress(route, b).arrived, true);
      expect(
        walkingProgress(
          route,
          const Coordinates(latitude: 36.192, longitude: -115.279),
        ).offRouteMeters,
        greaterThan(200),
      );
    },
  );
  test(
    'service requests bounded pedestrian graph and reuses it for navigation',
    () async {
      var requests = 0;
      final service = PedestrianTripService(
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.host, 'overpass-api.de');
          expect(
            Uri.splitQueryString(request.body)['data'],
            contains('footway|path|pedestrian|steps|cycleway'),
          );
          return http.Response(jsonEncode(network()), 200);
        }),
      );
      addTearDown(service.client.close);
      expect(await service.walkAlternatives(a, b), hasLength(2));
      expect(
        await service.walkAlternatives(
          const Coordinates(latitude: 36.19, longitude: -115.2799),
          b,
        ),
        isNotEmpty,
      );
      expect(requests, 1);
    },
  );
  test('partial map data is an error, never a partial usable path', () async {
    final service = PedestrianTripService(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({...network(), 'remark': 'timeout'}), 200),
      ),
    );
    addTearDown(service.client.close);
    await expectLater(service.walkAlternatives(a, b), throwsFormatException);
  });
  test('foreground tracking keeps permission choice, drops poor/stale fixes and stops on opt-out', () async {
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final gps = LiveLocation();
    final location = AppLocation(settings, service: gps);
    await location.choose(LocationChoice.session);
    location.startTracking();
    final now = DateTime.now();
    gps.updates.add(WalkingLocationFix(b, now, accuracy: 90));
    expect(location.position, same(a));
    gps.updates.add(
      WalkingLocationFix(
        b,
        now.subtract(const Duration(minutes: 1)),
        accuracy: 5,
      ),
    );
    expect(location.position, same(a));
    gps.updates.add(
      WalkingLocationFix(b, now, accuracy: 5, heading: 90, speed: 1),
    );
    expect(location.position, same(b));
    expect(gps.prompts, 1);
    location.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(gps.updates.hasListener, false);
    location.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(gps.subscriptions, 2);
    expect(gps.prompts, 1);
    await location.choose(LocationChoice.never);
    expect(gps.updates.hasListener, false);
    expect(location.position, isNull);
    gps.updates.add(WalkingLocationFix(a, now.add(const Duration(seconds: 1))));
    expect(location.position, isNull);
    location.dispose();
    settings.dispose();
    await gps.updates.close();
  });
}
