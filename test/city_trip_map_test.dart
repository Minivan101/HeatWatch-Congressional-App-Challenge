import 'dart:async';

import 'package:heatwatch/core/services/location_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/shade_route/presentation/city_trip_panel.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';

import 'shared_location_test.dart' show TestPosition;
import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

const origin = Coordinates(latitude: 36.19, longitude: -115.28);
const end = Coordinates(latitude: 36.195, longitude: -115.285);

class MapService extends CityTripService {
  int walks = 0, searches = 0;
  final shadeDurations = <double>[];
  Coordinates? usedStart, usedEnd;
  List<Coordinates> usedVia = [];
  Completer<List<CityWalkingRoute>>? pending;
  @override
  Future<List<CityPlace>> search(String query) async {
    searches++;
    if (query == 'Test starting address') {
      return [
        const CityPlace(
          'Test-only starting place',
          'Las Vegas test fixture',
          origin,
        ),
      ];
    }
    return [
      const CityPlace('Test-only destination', 'Las Vegas test fixture', end),
    ];
  }

  @override
  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates destination, {
    List<Coordinates> via = const [],
  }) async {
    walks++;
    usedStart = start;
    usedEnd = destination;
    usedVia = List.of(via);
    if (pending != null) return pending!.future;
    return [
      for (var i = 0; i < 2; i++)
        CityWalkingRoute(
          WalkingGeometry(
            points: [
              start,
              ...via,
              if (via.isEmpty)
                Coordinates(latitude: 36.191 + i * .001, longitude: -115.282),
              destination,
            ],
            durationSeconds: 300 + i * 60,
            sourceUrl: 'https://example.com/test-only',
            accessReviewed: false,
          ),
          500 + i * 100,
        ),
    ];
  }
}

class LiveMapPosition extends TestPosition {
  final stream = StreamController<WalkingLocationFix>.broadcast(sync: true);
  @override
  Stream<WalkingLocationFix> watchPosition() => stream.stream;
}

void main() {
  test(
    'planning accepts the official northern city edge with shadow buffer',
    () {
      const cityEdge = Coordinates(latitude: 36.4014928356, longitude: -115.3);
      expect(CityTripService.isInPlanningArea(cityEdge), true);
      expect(() => CityTripService.validatePoint(cityEdge), returnsNormally);
      expect(
        CityTripService.isInPlanningArea(
          const Coordinates(latitude: 36.402, longitude: -115.3),
        ),
        false,
      );
    },
  );

  Future<(AppLocation, TestPosition)> mount(
    WidgetTester tester,
    MapService service, {
    bool gps = true,
    TestPosition? liveGps,
    ValueNotifier<CoolingDestination?>? destination,
    Size size = const Size(420, 850),
    double scale = 1,
    SavedPlaces? favorites,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final gpsService = liveGps ?? TestPosition();
    final location = AppLocation(settings, service: gpsService);
    await location.choose(gps ? LocationChoice.session : LocationChoice.never);
    final now = DateTime.now().toUtc();
    final weather = WeatherRepository(
      weather: WeatherFake((p) async => readingAt(p, now)),
      alerts: AlertsFake((p) async => alertReading(p, now, [])),
      cache: WeatherCache(),
    );
    final target = destination ?? ValueNotifier<CoolingDestination?>(null);
    if (destination == null) addTearDown(target.dispose);
    await tester.pumpWidget(
      LocationScope(
        location: location,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: favorites == null
                ? child!
                : SavedPlacesScope(places: favorites, child: child!),
          ),
          home: Scaffold(
            body: ValueListenableBuilder<CoolingDestination?>(
              valueListenable: target,
              builder: (context, selection, _) => CityTripPanel(
                destination: selection,
                service: service,
                tilesEnabled: false,
                weather: weather,
                shadeCalculator: (route, _) async {
                  service.shadeDurations.add(route.geometry.durationSeconds);
                  return {'shade': route.distanceMeters == 500 ? .1 : null};
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() {
      location.dispose();
      settings.dispose();
      service.client.close();
    });
    return (location, gpsService);
  }

  testWidgets('no GPS opens a city-wide Las Vegas view', (tester) async {
    await mount(tester, MapService(), gps: false);
    final camera = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera;
    expect(camera.center.latitude, closeTo(36.1699, 1e-6));
    expect(camera.center.longitude, closeTo(-115.1398, 1e-6));
    expect(camera.zoom, 12);
  });

  testWidgets(
    'outside GPS stays real but cannot recenter away from Las Vegas',
    (tester) async {
      const outside = Coordinates(latitude: 34.0522, longitude: -118.2437);
      final result = Completer<Coordinates>()..complete(outside);
      final service = MapService();
      final (location, _) = await mount(
        tester,
        service,
        liveGps: TestPosition(pending: result),
      );
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(location.position, same(outside));
      expect(map.mapController!.camera.center.latitude, closeTo(36.1699, 1e-6));
      expect(map.mapController!.camera.zoom, 12);
      await tester.tap(find.byTooltip('Center on my location'));
      await tester.pumpAndSettle();
      expect(
        map.mapController!.camera.center.longitude,
        closeTo(-115.1398, 1e-6),
      );
      expect(
        find.textContaining('Your location is outside Las Vegas'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Show entire route'));
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.center.latitude, closeTo(36.1699, 1e-6));
      expect(location.position, same(outside));
      expect(service.walks, 0);
    },
  );

  testWidgets('late out-of-area GPS does not move the city default', (
    tester,
  ) async {
    final result = Completer<Coordinates>()
      ..complete(const Coordinates(latitude: 34.0522, longitude: -118.2437));
    final (location, _) = await mount(
      tester,
      MapService(),
      gps: false,
      liveGps: TestPosition(pending: result),
    );
    await location.choose(LocationChoice.session);
    await tester.pumpAndSettle();
    final camera = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera;
    expect(camera.center.latitude, closeTo(36.1699, 1e-6));
    expect(camera.center.longitude, closeTo(-115.1398, 1e-6));
  });

  testWidgets('Las Vegas GPS still centers on the actual starting point', (
    tester,
  ) async {
    await mount(tester, MapService());
    final camera = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera;
    expect(camera.center.latitude, closeTo(origin.latitude, 1e-6));
    expect(camera.center.longitude, closeTo(origin.longitude, 1e-6));
    expect(camera.zoom, 14);
  });

  Future<void> selectDestination(
    WidgetTester tester, {
    bool waitForRoute = true,
  }) async {
    await tester.tap(find.byKey(const ValueKey('route-destination-field')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Destination place or address'),
      'Test destination',
    );
    await tester.tap(find.byTooltip('Search places'));
    await tester.pumpAndSettle();
    if (find.text('Test-only destination').evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text('Test-only destination'),
        70,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .last,
      );
    }
    await tester.ensureVisible(find.text('Test-only destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test-only destination'));
    if (waitForRoute) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets(
    'navigation follows heading, hides percentages, stops on location opt-out',
    (tester) async {
      final gps = LiveMapPosition();
      final service = MapService();
      final (location, _) = await mount(tester, service, liveGps: gps);
      await selectDestination(tester);
      final button = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(
        button,
        120,
        scrollable: find.byType(DraggableScrollableSheet).evaluate().isEmpty
            ? find.byType(Scrollable).first
            : find
                  .descendant(
                    of: find.byType(DraggableScrollableSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      const current = Coordinates(latitude: 36.1901, longitude: -115.2802);
      gps.stream.add(
        WalkingLocationFix(
          current,
          DateTime.now(),
          accuracy: 5,
          heading: 90,
          speed: 1,
        ),
      );
      await tester.pump();
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(current.latitude, 1e-6),
      );
      expect(map.mapController!.camera.rotation, closeTo(-90, 1e-6));
      expect(find.textContaining('mi remaining'), findsWidgets);
      expect(find.textContaining('%'), findsNothing);
      expect(service.walks, 1);
      expect(gps.calls, 1);
      await location.choose(LocationChoice.never);
      await tester.pumpAndSettle();
      expect(gps.stream.hasListener, false);
      expect(find.text('Stop navigation'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await gps.stream.close();
    },
  );

  testWidgets('manual recalculation while walking retains route and GPS', (
    tester,
  ) async {
    final gps = LiveMapPosition();
    final service = MapService();
    final (location, _) = await mount(tester, service, liveGps: gps);
    await selectDestination(tester);
    final scroll = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    final start = find.byKey(const ValueKey('walking-navigation-toggle'));
    await tester.scrollUntilVisible(start, 120, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    gps.stream.add(WalkingLocationFix(origin, DateTime.now(), accuracy: 5));
    await tester.pumpAndSettle();
    expect(location.tracking, true);
    service.pending = Completer<List<CityWalkingRoute>>();
    final calculate = find.byKey(const ValueKey('route-refresh-button'));
    await tester.scrollUntilVisible(calculate, 300, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.tap(calculate);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(location.tracking, true);
    expect(
      tester
          .widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>))
          .polylines,
      hasLength(1),
    );
    service.pending!.complete([
      CityWalkingRoute(
        WalkingGeometry(
          points: [origin, end],
          durationSeconds: 300,
          sourceUrl: 'https://example.com/test-only',
          accessReviewed: false,
        ),
        500,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(location.tracking, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await gps.stream.close();
  });

  testWidgets(
    'sustained off-route GPS recalculates once; late reroute cannot survive opt-out',
    (tester) async {
      final gps = LiveMapPosition();
      final service = MapService();
      final (location, _) = await mount(tester, service, liveGps: gps);
      await selectDestination(tester);
      final button = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(
        button,
        120,
        scrollable: find.byType(DraggableScrollableSheet).evaluate().isEmpty
            ? find.byType(Scrollable).first
            : find
                  .descendant(
                    of: find.byType(DraggableScrollableSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final now = DateTime.now();
      const off = Coordinates(latitude: 36.192, longitude: -115.28);
      gps.stream.add(
        WalkingLocationFix(
          off,
          now.subtract(const Duration(seconds: 7)),
          accuracy: 5,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(service.walks, 1);
      service.pending = Completer<List<CityWalkingRoute>>();
      gps.stream.add(
        WalkingLocationFix(
          off,
          now.subtract(const Duration(seconds: 1)),
          accuracy: 5,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(service.walks, 2);
      await location.choose(LocationChoice.never);
      service.pending!.complete([
        CityWalkingRoute(
          WalkingGeometry(
            points: [off, end],
            durationSeconds: 300,
            sourceUrl: 'https://example.com/test-only',
            accessReviewed: false,
          ),
          500,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('walking-route-0')), findsNothing);
      expect(gps.stream.hasListener, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await gps.stream.close();
    },
  );

  testWidgets(
    'panning pauses follow and recenter resumes it without refetching routes',
    (tester) async {
      final gps = LiveMapPosition();
      final service = MapService();
      await mount(tester, service, liveGps: gps);
      await selectDestination(tester);
      final button = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(
        button,
        120,
        scrollable: find.byType(DraggableScrollableSheet).evaluate().isEmpty
            ? find.byType(Scrollable).first
            : find
                  .descendant(
                    of: find.byType(DraggableScrollableSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final now = DateTime.now();
      const p = Coordinates(latitude: 36.1901, longitude: -115.2802);
      gps.stream.add(
        WalkingLocationFix(
          p,
          now.subtract(const Duration(seconds: 2)),
          accuracy: 5,
        ),
      );
      await tester.pump();
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      map.options.onPositionChanged!(map.mapController!.camera, true);
      map.mapController!.move(const LatLng(36.193, -115.282), 15);
      const next = Coordinates(latitude: 36.1902, longitude: -115.2804);
      gps.stream.add(
        WalkingLocationFix(
          next,
          now.subtract(const Duration(seconds: 1)),
          accuracy: 5,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(map.mapController!.camera.center.latitude, closeTo(36.193, 1e-6));
      await tester.tap(find.byTooltip('Center on my location'));
      await tester.pump();
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(next.latitude, 1e-6),
      );
      expect(service.walks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await gps.stream.close();
    },
  );

  testWidgets(
    'typed starting place and destination route without GPS or name autocorrection',
    (tester) async {
      final service = MapService();
      final (location, _) = await mount(tester, service);
      await location.choose(LocationChoice.never);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('route-start-field')));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Start place or address');
      expect(tester.widget<TextField>(field).autocorrect, false);
      expect(tester.widget<TextField>(field).enableSuggestions, false);
      await tester.enterText(field, 'Test starting address');
      await tester.tap(find.byTooltip('Search places'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test-only starting place'));
      await tester.tap(find.text('Test-only starting place'));
      await tester.pumpAndSettle();
      expect(service.walks, 0);
      await selectDestination(tester);
      expect(service.usedStart, origin);
      expect(service.usedEnd, end);
      expect(service.searches, 2);
      expect(service.walks, 1);
      expect(find.byType(PolylineLayer<int>), findsOneWidget);
      expect(service.shadeDurations, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final keepGps in [true, false]) {
    testWidgets(
      'cooling map current-location handoff replaces a manual start; GPS=$keepGps',
      (tester) async {
        final target = ValueNotifier<CoolingDestination?>(null);
        addTearDown(target.dispose);
        final service = MapService();
        final (location, gps) = await mount(
          tester,
          service,
          destination: target,
        );
        await tester.tap(find.byKey(const ValueKey('route-start-field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose on map'));
        await tester.pumpAndSettle();
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
          const TapPosition(Offset.zero, Offset.zero),
          const LatLng(36.192, -115.281),
        );
        await tester.pumpAndSettle();
        await selectDestination(tester);
        expect(service.usedStart?.latitude, 36.192);
        if (!keepGps) {
          await location.choose(LocationChoice.never);
          await tester.pumpAndSettle();
        }
        final before = service.walks;

        target.value = const CoolingDestination(
          id: 'test-only',
          name: 'Test-only destination',
          address: 'Las Vegas test fixture',
          location: end,
          sourceUrl: 'https://example.com/test-only',
          precision: 'test',
          startFromCurrentLocation: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('Selected start'), findsNothing);
        expect(service.walks, keepGps ? before + 1 : before);
        if (keepGps) expect(service.usedStart?.latitude, origin.latitude);
        expect(gps.calls, 1);
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'GPS is default; choosing destination draws real returned alternatives; selection updates map',
    (tester) async {
      final service = MapService();
      final (_, gps) = await mount(tester, service);
      expect(find.text('Your location'), findsOneWidget);
      await selectDestination(tester);
      expect(service.usedStart?.latitude, origin.latitude);
      expect(service.walks, 1);
      expect(gps.calls, 1);
      final layer = tester.widget<PolylineLayer<int>>(
        find.byType(PolylineLayer<int>),
      );
      expect(layer.polylines.length, 1);
      expect(layer.polylines.last.hitValue, 0);
      final card = find.byKey(const ValueKey('best-route-choice'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      final updated = tester.widget<PolylineLayer<int>>(
        find.byType(PolylineLayer<int>),
      );
      expect(updated.polylines.length, 1);
      expect(updated.polylines.last.hitValue, 0);
      expect(find.textContaining('Shade: data unavailable'), findsNothing);
      expect(find.byKey(const ValueKey('best-route-choice')), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'walking duration uses provider estimates without a pace override',
    (tester) async {
      final service = MapService();
      await mount(tester, service);
      await selectDestination(tester);
      final button = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(
        button,
        100,
        scrollable: find.byType(DraggableScrollableSheet).evaluate().isEmpty
            ? find.byType(Scrollable).first
            : find
                  .descendant(
                    of: find.byType(DraggableScrollableSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
      );
      await tester.pumpAndSettle();
      expect(service.walks, 1);
      expect(service.shadeDurations, [300.0, 360.0]);
      expect(find.byTooltip('Adjust walking pace'), findsNothing);
      expect(find.byKey(const ValueKey('trip-duration-input')), findsNothing);
      expect(find.text('5 min'), findsWidgets);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'favorites save departure and arrival independently of the route',
    (tester) async {
      String? stored;
      final favorites = SavedPlaces(
        read: () async => null,
        write: (value) async => stored = value,
      );
      await favorites.load();
      addTearDown(favorites.dispose);
      final service = MapService();
      await mount(tester, service, favorites: favorites);
      expect(find.byKey(const ValueKey('favorite-departure')), findsNothing);
      await selectDestination(tester);
      await tester.tap(find.byTooltip('Save arrival: Test-only destination'));
      await tester.pumpAndSettle();
      expect(favorites.favorites.single.point, end);
      expect(favorites.favorites.single.name, 'Test-only destination');
      await tester.tap(find.byKey(const ValueKey('route-start-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Start place or address'),
        'Test starting address',
      );
      await tester.tap(find.byTooltip('Search places'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test-only starting place'));
      await tester.tap(find.text('Test-only starting place'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Save departure: Test-only starting place'),
      );
      await tester.pumpAndSettle();
      expect(favorites.favorites.map((p) => p.point), [end, origin]);
      expect(favorites.favorites.map((p) => p.name), [
        'Test-only destination',
        'Test-only starting place',
      ]);
      await tester.tap(find.byTooltip('Unsave arrival: Test-only destination'));
      await tester.pumpAndSettle();
      expect(favorites.favorites.single.point, origin);
      final restored = SavedPlaces(
        read: () async => stored,
        write: (_) async {},
      );
      await restored.load();
      expect(restored.favorites.single.point.latitude, origin.latitude);
      expect(restored.favorites.single.point.longitude, origin.longitude);
      expect(restored.favorites.single.name, 'Test-only starting place');
      restored.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'map pins edit either endpoint; a manual start survives GPS being turned off',
    (tester) async {
      final service = MapService();
      final (location, gps) = await mount(tester, service);
      await tester.tap(find.byKey(const ValueKey('route-start-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
        const TapPosition(Offset.zero, Offset.zero),
        const LatLng(36.192, -115.281),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected start'), findsOneWidget);
      await location.choose(LocationChoice.never);
      await tester.pumpAndSettle();
      await selectDestination(tester);
      expect(service.usedStart?.latitude, 36.192);
      expect(gps.calls, 1);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'missing GPS stays explicit; short screens and larger text remain usable',
    (tester) async {
      final service = MapService();
      await mount(
        tester,
        service,
        gps: false,
        size: const Size(850, 380),
        scale: 1.5,
      );
      expect(find.text('Location unavailable · tap to choose'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      await selectDestination(tester);
      expect(service.walks, 0);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('route-destination-field')),
          matching: find.text('Test-only destination'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'late GPS-origin route cannot reappear after location is turned off',
    (tester) async {
      final service = MapService()
        ..pending = Completer<List<CityWalkingRoute>>();
      final (location, _) = await mount(tester, service);
      await selectDestination(tester, waitForRoute: false);
      expect(service.walks, 1);
      await location.choose(LocationChoice.never);
      service.pending!.complete([
        CityWalkingRoute(
          WalkingGeometry(
            points: [origin, end],
            durationSeconds: 300,
            sourceUrl: 'https://example.com/test-only',
            accessReviewed: false,
          ),
          500,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('walking-route-0')), findsNothing);
      expect(
        tester
            .widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>))
            .polylines,
        isEmpty,
      );
      expect(tester.takeException(), null);
    },
  );
}
