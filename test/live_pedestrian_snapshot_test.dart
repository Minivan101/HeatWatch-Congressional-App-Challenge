import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/settings/route_preference.dart';
import 'package:heatwatch/features/shade_route/services/route_preference_selector.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final path = Platform.environment['HEATWATCH_PUBLIC_PEDESTRIAN_SNAPSHOT'];
  test(
    'public downtown Las Vegas snapshot routes on the pedestrian graph',
    () async {
      final data =
          jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;
      const pairs = [
        (
          Coordinates(latitude: 36.17193, longitude: -115.14460),
          Coordinates(latitude: 36.17030, longitude: -115.14070),
        ),
        (
          Coordinates(latitude: 36.17080, longitude: -115.14240),
          Coordinates(latitude: 36.16996, longitude: -115.14040),
        ),
      ];
      final report = <Map<String, dynamic>>[];
      final calculator = RouteShadeRepository();
      for (var i = 0; i < pairs.length; i++) {
        final (start, end) = pairs[i];
        final routes = PedestrianGraph(data).routes([start, end]);
        expect(routes, isNotEmpty);
        final shade = <double?>[];
        final coverage = <double?>[];
        final timed = <Map>[];
        final metrics = <RoutePreferenceMetric>[];
        for (final route in routes) {
          final result = await calculator.calculate(
            route.geometry,
            DateTime.utc(2026, 10, 10, 17),
          );
          shade.add((result['shade'] as num?)?.toDouble());
          coverage.add((result['coverage'] as num?)?.toDouble());
          expect(result['sunAtDeparture'], isNotNull);
          final times = result['timeTotals'] as Map;
          expect(
            times.values.fold<double>(
              0,
              (sum, v) => sum + (v as num).toDouble(),
            ),
            closeTo(route.geometry.durationSeconds, .01),
          );
          timed.add(times);
          metrics.add(
            RoutePreferenceMetric(
              route.geometry.durationSeconds,
              timeTotals: times,
            ),
          );
        }
        report.add({
          'pair': i + 1,
          'developmentShadeFractions': shade,
          'dataCoverageFractions': coverage,
          'candidates': routes.length,
          'developmentTimeTotals': timed,
          'preferenceIndices': {
            for (final preference in RoutePreference.values)
              preference.name: selectPreferredRoute(preference, metrics).index,
          },
          'meters': routes.map((r) => r.distanceMeters).toList(),
          'steps': routes.map((r) => r.steps.length).toList(),
        });
      }

      // ignore: avoid_print
      print(jsonEncode({'publicSnapshotResults': report}));
    },
    skip: path == null
        ? 'Set public-snapshot path for explicit live-source check'
        : false,
  );
}
