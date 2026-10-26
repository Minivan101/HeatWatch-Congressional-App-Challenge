import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_repository.dart';

class LocalFiles extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

Coordinates point(Map p) => Coordinates(
  latitude: (p['latitude'] as num).toDouble(),
  longitude: (p['longitude'] as num).toDouble(),
);
void main() {
  test('six public Las Vegas areas use real walking geometry and production shade tiles', () async {
    final cases = jsonDecode(
      File('test/fixtures/routes/vegas_public_endpoints.json')
          .readAsStringSync(),
    ) as List;
    const planner = bool.fromEnvironment('HEATWATCH_PUBLIC_USE_PLANNER');
    final service = planner ? PedestrianTripService() : CityTripService();
    final shade = RouteShadeRepository(bundle: LocalFiles());
    final report = <Map<String, dynamic>>[];
    var failures = 0;
    final times = [
      '2026-06-21T15:00:00Z',
      '2026-06-21T20:00:00Z',
      '2026-10-07T19:00:00Z',
      '2026-10-08T06:00:00Z',
    ];
    try {
      for (final c in cases) {
        final row = <String, dynamic>{
          'name': c['name'],
          'start': {
            'latitude': c['start']['latitude'],
            'longitude': c['start']['longitude'],
          },
          'end': {
            'latitude': c['end']['latitude'],
            'longitude': c['end']['longitude'],
          },
        };
        final timer = Stopwatch()..start();
        try {
          final routes = await service.walkAlternatives(
            point(c['start']),
            point(c['end']),
          );
          row['routes'] = [];
          for (final route in routes) {
            final results = [];
            for (final at in times) {
              final result = await shade.calculate(
                route.geometry,
                DateTime.parse(at),
              );
              final totals = result['totals'] as Map;
              final sum = totals.values.fold<double>(
                0,
                (v, s) => v + (s as num).toDouble(),
              );
              expect(sum, closeTo(result['distance'] as double, 0.001));
              if (result['shade'] != null) {
                expect(result['shade'], inInclusiveRange(0, 1));
              }
              if (result['coverage'] != null) {
                expect(result['coverage'], inInclusiveRange(0, 1));
              }
              if (at == times.last) {
                expect(result['shade'], null);
                expect(
                  result['night'],
                  closeTo(result['distance'] as double, 0.001),
                );
              }
              results.add({
                ...result,
                'segments': (result['segments'] as List).length,
              });
            }
            (row['routes'] as List).add({
              'distanceMeters': route.distanceMeters,
              'durationSeconds': route.geometry.durationSeconds,
              'geometryPoints': route.geometry.points.length,
              'sourceUrl': route.geometry.sourceUrl,
              'accessReviewed': route.geometry.accessReviewed,
              'shadeChecks': results,
            });
          }
          row['status'] = 'passed';
        } catch (e) {
          row['status'] = 'failed';
          row['error'] = e.toString();
          failures++;
        }
        row['elapsedMilliseconds'] = timer.elapsedMilliseconds;
        report.add(row);
        debugPrint(
          '${row['name']}: ${row['status']} (${timer.elapsedMilliseconds}ms)',
        );
      }
      final typed = [];
      for (final q in ['The Meadows School', 'Montagna Drive']) {
        final found = await service.search(q);
        expect(found, isNotEmpty);
        typed.add({
          'query': q,
          'matches': found.length,
          'firstName': found.first.name,
          'latitude': found.first.point.latitude,
          'longitude': found.first.point.longitude,
        });
      }
      File(
        const String.fromEnvironment(
          'HEATWATCH_ROUTE_REPORT',
          defaultValue: '/private/tmp/heatwatch-live-vegas-route-report.json',
        ),
      ).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'scope': 'Six public endpoint pairs, returned candidates and four instants; not all possible routes or physical shade accuracy.',
          'cases': report,
          'typedSearch': typed,
        }),
      );
      expect(failures, 0);
    } finally {
      service.client.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
