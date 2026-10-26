import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_repository.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

import 'route_shade_calculator_test.dart' show FileAssets;

Map<String, dynamic> source() => jsonDecode(
  File('docs/research/vegas-long-foot-route-2026-10-10.json')
      .readAsStringSync(),
) as Map<String, dynamic>;
void main() {
  test(
    'real long Vegas foot paths retain walking steps, geometry and timing',
    () {
      final paths = CityTripService.parseAlternatives(source());
      expect(paths, hasLength(2));
      expect(paths.first.distanceMeters, closeTo(17579.6, .01));
      expect(paths.last.geometry.durationSeconds, greaterThan(14400));
      for (final r in paths) {
        expect(r.geometry.points.length, greaterThan(800));
        expect(r.steps.length, greaterThan(50));
        expect(r.steps.first.atMeters, 0);
        expect(r.steps.last.instruction, 'Arrive at your destination');
        expect(r.steps.last.atMeters, closeTo(r.distanceMeters, 5));
        final progress = WalkingRouteTracker().update(r, r.geometry.points[20]);
        expect(progress.offRouteMeters, lessThan(.1));
        expect(progress.remainingMeters, greaterThan(10000));
        expect(progress.instruction, isNotEmpty);
      }
    },
  );
  test(
    'long walks use foot provider, request instructions and reuse cache',
    () async {
      var calls = 0;
      final service = PedestrianTripService(
        client: MockClient((req) async {
          calls++;
          expect(req.method, 'GET');
          expect(req.url.host, 'routing.openstreetmap.de');
          expect(req.url.path, contains('/routed-foot/route/v1/foot/'));
          expect(req.url.queryParameters['steps'], 'true');
          return http.Response(jsonEncode(source()), 200);
        }),
      );
      addTearDown(service.client.close);
      const start = Coordinates(latitude: 36.191439, longitude: -115.302102);
      const end = Coordinates(latitude: 36.1672, longitude: -115.1485);
      final r = await service.walkAlternatives(start, end);
      expect(r, hasLength(2));
      expect(await service.walkAlternatives(start, end), same(r));
      expect(calls, 1);
    },
  );
  test('reject non-walking instructions, inconsistent distances and oversized trips', () {
    for (final field in ['mode', 'distance', 'limit', 'duration']) {
      final d = source();
      final r = d['routes'][0];
      if (field == 'mode') r['legs'][0]['steps'][1]['mode'] = 'driving';
      if (field == 'distance') r['legs'][0]['steps'][1]['distance'] = 50000;
      if (field == 'limit') r['distance'] = 50001;
      if (field == 'duration') r['duration'] = 43201;
      expect(
        () => CityTripService.parseRoute(d),
        throwsFormatException,
        reason: field,
      );
    }
  });
  test('actual long routes calculate corridor shade over four hours with time-varying sun', () async {
    final paths = CityTripService.parseAlternatives(source());
    final repo = RouteShadeRepository(bundle: FileAssets());
    final reports = <Map<String, dynamic>>[];
    for (final route in paths) {
      final at = DateTime.parse('2026-06-21T15:00:00Z');
      final result = await repo.calculate(route.geometry, at);
      expect(result['distance'], greaterThan(17000));
      expect(result['coverage'], greaterThanOrEqualTo(.9));
      expect(result['shade'], isNotNull);
      expect(
        (result['sunAtArrival'] as Map)['azimuth'],
        isNot((result['sunAtDeparture'] as Map)['azimuth']),
      );
      expect(
        DateTime.parse(result['arrival'] as String).difference(at).inSeconds,
        closeTo(route.geometry.durationSeconds, 1),
      );
      final classified = (result['totals'] as Map).values
          .cast<double>()
          .fold<double>(0, (a, b) => a + b);
      expect(classified, closeTo(result['distance'] as double, .01));
      reports.add({
        for (final key in [
          'distance',
          'duration',
          'shade',
          'coverage',
          'arrival',
          'sunAtDeparture',
          'sunAtArrival',
          'totals',
        ])
          key: result[key],
      });
    }
    File('${Directory.systemTemp.path}/heatwatch-long-shade-check.json')
        .writeAsStringSync(jsonEncode(reports));
  });
}
