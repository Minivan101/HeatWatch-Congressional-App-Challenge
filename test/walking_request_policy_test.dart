import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';
import 'dart:async';

import 'city_trip_service_test.dart' show route;

import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/walking_request_policy.dart';

void main() {
  test(
    'queued map work honors a retry window set by the preceding request',
    () async {
      var now = DateTime.utc(2026, 10, 11, 17), maps = 0;
      final release = Completer<http.Response>();
      final service = PedestrianTripService(
        now: () => now,
        client: MockClient((request) async {
          if (request.method == 'POST') {
            maps++;
            return release.future;
          }
          return http.Response(jsonEncode(route()), 200);
        }),
      );
      addTearDown(service.client.close);
      const a = Coordinates(latitude: 36.19, longitude: -115.28),
          b = Coordinates(latitude: 36.191, longitude: -115.281);
      final calls = [service.walk(a, b), service.walk(a, b)];
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 6));
      release.complete(
        http.Response('busy', 429, headers: {'retry-after': '120'}),
      );
      await Future.wait(calls);
      expect(maps, 1);
    },
  );

  test(
    'foot-route cache expires instead of retaining yesterday’s access data',
    () async {
      var now = DateTime.utc(2026, 10, 11, 17), requests = 0;
      final service = CityTripService(
        now: () => now,
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(route()), 200);
        }),
      );
      addTearDown(service.client.close);
      const a = Coordinates(latitude: 36.19, longitude: -115.28),
          b = Coordinates(latitude: 36.191, longitude: -115.281);
      await service.walk(a, b);
      now = now.add(const Duration(minutes: 29));
      await service.walk(a, b);
      expect(requests, 1);
      now = now.add(const Duration(minutes: 2));
      await service.walk(a, b);
      expect(requests, 2);
    },
  );
  test('Overpass Retry-After prevents repeated map downloads while foot fallback is cached', () async {
    var now = DateTime.utc(2026, 10, 11, 17), maps = 0, foot = 0;
    final service = PedestrianTripService(
      now: () => now,
      client: MockClient((r) async {
        if (r.method == 'POST') {
          maps++;
          return http.Response('busy', 429, headers: {'retry-after': '120'});
        }
        foot++;
        return http.Response(jsonEncode(route()), 200);
      }),
    );
    addTearDown(service.client.close);
    const a = Coordinates(latitude: 36.19, longitude: -115.28),
        b = Coordinates(latitude: 36.191, longitude: -115.281);
    await service.walk(a, b);
    now = now.add(const Duration(seconds: 10));
    await service.walk(a, b);
    expect(maps, 1);
    expect(foot, 1);
    now = now.add(const Duration(minutes: 3));
    await service.walk(a, b);
    expect(maps, 2);
    expect(foot, 1);
  });
  test(
    'retry policy accepts seconds and GMT dates and rejects invalid dates',
    () {
      final now = DateTime.utc(2026, 10, 11, 10);
      expect(walkingRetryTime('120', now), now.add(const Duration(minutes: 2)));
      expect(
        walkingRetryTime('Sun, 11 Oct 2026 10:02:00 GMT', now),
        now.add(const Duration(minutes: 2)),
      );
      for (final value in [
        'negative',
        '-1',
        'Sun, 32 Oct 2026 10:00:00 GMT',
        'Sun, 01 Bad 2026 10:00:00 GMT',
      ]) {
        expect(walkingRetryTime(value, now), null);
      }
    },
  );
  for (final code in [429, 503]) {
    test(
      'HTTP $code blocks repeated walking requests until Retry-After expires',
      () async {
        var now = DateTime.utc(2026, 10, 11, 10), calls = 0;
        final service = CityTripService(
          now: () => now,
          client: MockClient((_) async {
            calls++;
            return calls == 1
                ? http.Response('busy', code, headers: {'retry-after': '120'})
                : http.Response('{}', 200);
          }),
        );
        addTearDown(service.client.close);
        const a = Coordinates(latitude: 36.19, longitude: -115.28),
            b = Coordinates(latitude: 36.191, longitude: -115.281);
        await expectLater(service.walk(a, b), throwsFormatException);
        await expectLater(service.walk(a, b), throwsFormatException);
        expect(calls, 1);
        now = now.add(const Duration(minutes: 3));
        await expectLater(service.walk(a, b), throwsFormatException);
        expect(calls, 2);
      },
    );
  }
}
