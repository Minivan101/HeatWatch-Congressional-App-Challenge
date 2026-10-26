import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/features/cool_spots/presentation/cool_spots_page.dart';
import 'package:heatwatch/features/heat_guard/presentation/heat_guard_page.dart';
import 'package:heatwatch/features/shade_route/presentation/shade_model_preview.dart';
import 'package:heatwatch/features/shade_route/presentation/shade_route_page.dart';
import 'package:heatwatch/features/shade_route/services/shade_route_service.dart';
import 'package:integration_test/integration_test.dart';

import 'package:heatwatch/main.dart' as heatwatch;

class _LocationClient implements LocationClient {
  _LocationClient(this.state);
  final String state;

  @override
  Future<bool> isLocationServiceEnabled() async => state != 'disabled';

  @override
  Future<LocationPermission> checkPermission() async => switch (state) {
    'denied' => LocationPermission.denied,
    'permanent' => LocationPermission.deniedForever,
    _ => LocationPermission.whileInUse,
  };

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  @override
  Future<Coordinates> getCurrentPosition() async =>
      const Coordinates(latitude: 34.00003, longitude: -118.00078);
}

class _RouteService extends ShadeRouteService {
  _RouteService(this.load);
  final Future<Map<String, dynamic>> Function() load;

  @override
  Future<Map<String, dynamic>> getDemoRoutes(ShadeRouteTrip trip) => load();
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Expected text did not appear: $finder');
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.25);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'legacy local emulator features complete their development journeys',
    (tester) async {
      await heatwatch.main();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ShadeModelPreview()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final routeButton = find.text('Send saved trip to local backend');
      await _tapVisible(tester, routeButton);
      await _waitFor(tester, find.textContaining('saved trip matched'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolSpotsPage(
              dataLoader: () async => {
                'dataset': jsonDecode(
                  await rootBundle.loadString(
                    'data/cooling_centers/clark_county_june_2026.json',
                  ),
                ),
                'example': jsonDecode(
                  await rootBundle.loadString('assets/cool_spots_demo.json'),
                ),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('View detailed report'));
      final centersButton = find.text('Read local center records');
      await _tapVisible(tester, centersButton);
      await _waitFor(
        tester,
        find.textContaining('county records from the local Firestore emulator'),
      );
      expect(find.text('Past official listings — inactive'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HeatGuardPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conditions not loaded'), findsOneWidget);
      await _tapVisible(tester, find.text('View example scenarios'));
      final heatButton = find.text('Load local Heat Guard example');
      await _tapVisible(tester, heatButton);
      await _waitFor(
        tester,
        find.textContaining('No Weather API request was made'),
      );
    },
  );

  testWidgets(
    'malformed data fails safely and retry recovers in each feature',
    (tester) async {
      final route = jsonDecode(
        await rootBundle.loadString('assets/shade_demo.json'),
      ) as Map<String, dynamic>;
      final centers = jsonDecode(
        await rootBundle.loadString(
          'data/cooling_centers/clark_county_june_2026.json',
        ),
      );
      final business = jsonDecode(
        await rootBundle.loadString('assets/cool_spots_demo.json'),
      );
      final heat = jsonDecode(
        await rootBundle.loadString('assets/heat_guard_scenarios.json'),
      ) as Map<String, dynamic>;

      var routeCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShadeModelPreview(
                service: _RouteService(() async {
                  routeCalls++;
                  if (routeCalls == 1) {
                    return {
                      ...route,
                      'routes': [
                        {'id': 'broken', 'durationSeconds': -1},
                      ],
                    };
                  }
                  return route;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final routeButton = find.text('Send saved trip to local backend');
      await _tapVisible(tester, routeButton);
      await _waitFor(tester, find.textContaining('incomplete route data'));
      expect(find.text('Route 1'), findsNothing);
      await _tapVisible(tester, routeButton);
      await _waitFor(tester, find.textContaining('saved trip matched'));

      var centerCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolSpotsPage(
              dataLoader: () async {
                centerCalls++;
                if (centerCalls == 1) {
                  return {
                    'dataset': {
                      ...Map<String, dynamic>.from(centers as Map),
                      'sourceUrl': 'http://invalid.example',
                    },
                    'example': business,
                  };
                }
                return {'dataset': centers, 'example': business};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Saved place records could not be loaded.'),
        findsOneWidget,
      );
      await _tapVisible(tester, find.text('Retry saved records'));
      await _waitFor(tester, find.text('View detailed report'));
      await _tapVisible(tester, find.text('View detailed report'));
      await _waitFor(tester, find.text('Official cooling centers'));
      expect(find.text('Past official listings — inactive'), findsOneWidget);

      var heatCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeatGuardPage(
              scenarioLoader: () async {
                heatCalls++;
                if (heatCalls == 1) {
                  return {...heat, 'exampleAsOf': '2026-06-21T09:00:00'};
                }
                return heat;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('View example scenarios'));
      await tester.scrollUntilVisible(
        find.text('Examples could not be loaded.'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Examples could not be loaded.'), findsOneWidget);
      await _tapVisible(tester, find.text('Retry examples'));
      await _waitFor(tester, find.textContaining('Example severe alert'));
    },
  );

  for (final state in ['disabled', 'denied', 'permanent', 'granted']) {
    testWidgets('location permission UI: $state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShadeRoutePage(
              locationService: LocationService(client: _LocationClient(state)),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      final expected = switch (state) {
        'disabled' => 'Location services are off.',
        'denied' => 'Location access was denied.',
        'permanent' => 'Location access is off for HeatWatch.',
        _ => 'Location found: 34.000, -118.001',
      };
      expect(find.textContaining(expected), findsOneWidget);
    });
  }
}
