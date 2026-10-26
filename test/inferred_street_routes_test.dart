import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_repository.dart';
import 'package:heatwatch/core/models/coordinates.dart';

import 'pedestrian_navigation_test.dart' show network, a, b;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in [
    'residential',
    'living_street',
    'unclassified',
    'service',
    'tertiary',
    'secondary',
    'primary',
  ]) {
    test('inferred walking uses connected $kind street geometry', () {
      final data = network(
        tags: {'highway': kind, 'name': 'Public test street'},
      );
      (data['elements'] as List).removeLast();
      final route = PedestrianGraph(
        data,
        inferStreetWalking: true,
      ).routes([a, b]).first;
      expect(route.inferredStreetMeters, closeTo(route.distanceMeters, .01));
      expect(route.steps.first.instruction, contains('Public test street'));
      expect(route.geometry.accessReviewed, false);
    });
  }
  for (final tags in [
    {'highway': 'motorway', 'foot': 'yes'},
    {'highway': 'motorway_link'},
    {'highway': 'trunk'},
    {'highway': 'trunk_link'},
    {'highway': 'primary_link'},
    {'highway': 'residential', 'foot': 'no'},
    {'highway': 'residential', 'access': 'private'},
    {'highway': 'residential', 'motorroad': 'yes'},
    {'highway': 'primary', 'expressway': 'yes'},
    {'highway': 'residential', 'sidewalk': 'no'},
    {'highway': 'service', 'service': 'driveway'},
    {'highway': 'residential', 'access:conditional': 'yes @ (Mo-Fr)'},
    {'highway': 'residential', 'construction': 'yes'},
  ]) {
    test('street inference respects exclusion $tags', () {
      final data = network(tags: tags);
      (data['elements'] as List).removeLast();
      expect(
        () => PedestrianGraph(data, inferStreetWalking: true).routes([a, b]),
        throwsFormatException,
      );
    });
  }
  test('car one-way does not block walkers but foot one-way does', () {
    final data = network(tags: {'highway': 'residential', 'oneway': 'yes'});
    (data['elements'] as List).removeLast();
    expect(
      PedestrianGraph(data, inferStreetWalking: true).routes([b, a]),
      isNotEmpty,
    );
    (data['elements'] as List).last['tags']['oneway:foot'] = 'yes';
    expect(
      () => PedestrianGraph(data, inferStreetWalking: true).routes([b, a]),
      throwsFormatException,
    );
  });
  test('explicit footpaths have zero inferred street distance', () {
    final route = PedestrianGraph(
      network(),
      inferStreetWalking: true,
    ).routes([a, b]).first;
    expect(route.inferredStreetMeters, 0);
  });

  final path = Platform.environment['HEATWATCH_LIBRARY_STREET_SNAPSHOT'];
  test(
    'original public library trip works on inferred street network both ways',
    () async {
      final data =
          jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;
      const start = Coordinates(
        latitude: 36.19143950472907,
        longitude: -115.30210200475739,
      );
      const end = Coordinates(
        latitude: 36.2174216443873,
        longitude: -115.25929184419876,
      );
      final report = <Map<String, dynamic>>[];
      final calculator = RouteShadeRepository();
      for (final pair in [(start, end), (end, start)]) {
        final routes = PedestrianGraph(
          data,
          inferStreetWalking: true,
        ).routes([pair.$1, pair.$2]);
        expect(routes, isNotEmpty);
        for (final route in routes) {
          expect(route.inferredStreetMeters, greaterThan(0));
          final shade = await calculator.calculate(
            route.geometry,
            DateTime.utc(2026, 10, 10, 17),
          );
          expect(shade['sunAtDeparture'], isNotNull);
          report.add({
            'meters': route.distanceMeters,
            'inferredStreetMeters': route.inferredStreetMeters,
            'seconds': route.geometry.durationSeconds,
            'points': route.geometry.points.length,
            'developmentShade': shade['shade'],
            'coverage': shade['coverage'],
            'unknownMeters': (shade['totals'] as Map)['unknown'],
            'nightMeters': shade['night'],
          });
        }
      }
      // ignore: avoid_print
      print(jsonEncode({'libraryStreetRoutes': report}));
    },
    skip: path == null ? 'Explicit saved public-map snapshot required' : false,
  );
}
