import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:heatwatch/app.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/shade_route/presentation/city_trip_panel.dart';

import 'city_trip_map_test.dart' show MapService, LiveMapPosition, origin;
import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

void main({bool native = false}) {
  testWidgets(
    'full app retains a walking trip through weather and cooling tabs',
    (t) async {
      if (!native) {
        t.view.physicalSize = const Size(420, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
      }
      Future<void> settleIO() async {
        for (var i = 0; i < 100; i++) {
          await t.runAsync(() async {
            await t.pump();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          if (find
                  .byType(CircularProgressIndicator, skipOffstage: false)
                  .evaluate()
                  .isEmpty &&
              find
                  .byType(LinearProgressIndicator, skipOffstage: false)
                  .evaluate()
                  .isEmpty) {
            break;
          }
        }
        await t.pump(const Duration(milliseconds: 500));
        await t.pump();
      }

      final gps = LiveMapPosition();
      final service = MapService();
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await settings.load();
      await settings.update(preferencePromptSeen: true);
      final now = DateTime.now().toUtc();
      final weather = WeatherRepository(
        cache: WeatherCache(),
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: AlertsFake((p) async => alertReading(p, now, [])),
      );
      await t.runAsync(() async {
        await t.pumpWidget(
          HeatWatchApp(
            settings: settings,
            locationService: gps,
            walkingService: service,
            weatherRepository: weather,
            mapTilesEnabled: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() async {
          await t.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        if (find
                .byType(CircularProgressIndicator, skipOffstage: false)
                .evaluate()
                .isEmpty &&
            find
                .byType(LinearProgressIndicator, skipOffstage: false)
                .evaluate()
                .isEmpty) {
          break;
        }
      }
      await settleIO();
      await t.tap(find.text('Every time I open the app'));
      await settleIO();
      await t.tap(find.widgetWithText(NavigationDestination, 'ShadeMap'));
      await settleIO();
      final panel = find.byType(CityTripPanel);
      Finder scroll() =>
          find.descendant(of: panel, matching: find.byType(Scrollable)).first;
      Future<void> reveal(Finder f) async {
        if (f.evaluate().isEmpty) {
          t.state<ScrollableState>(scroll()).position.jumpTo(0);
          await t.pump();
          await t.scrollUntilVisible(
            f,
            100,
            scrollable: scroll(),
            maxScrolls: 100,
          );
        } else {
          await t.ensureVisible(f);
        }
        await settleIO();
      }

      await t.tap(find.byKey(const ValueKey('route-destination-field')));
      await settleIO();
      await t.enterText(
        find.widgetWithText(TextField, 'Destination place or address'),
        'Test destination',
      );
      await t.tap(find.byTooltip('Search places'));
      await settleIO();
      await t.runAsync(() async {
        await t.tap(find.text('Test-only destination'));
        await t.pump();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await settleIO();
      final toggle = find.byKey(const ValueKey('walking-navigation-toggle'));
      await reveal(toggle);
      await t.runAsync(() async {
        await t.tap(toggle);
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settleIO();
      gps.stream.add(
        WalkingLocationFix(
          origin,
          DateTime.now(),
          accuracy: 5,
          heading: 90,
          speed: 1,
        ),
      );
      await settleIO();
      expect(gps.stream.hasListener, true);
      await t.tap(find.byKey(const ValueKey('persistent-temperature')));
      await settleIO();
      expect(
        gps.stream.hasListener,
        true,
        reason: 'Checking UV/weather must not cancel walking',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(
        gps.stream.hasListener,
        false,
        reason: 'GPS must suspend in background',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleIO();
      expect(
        gps.stream.hasListener,
        true,
        reason: 'The active walk resumes without permission prompts',
      );
      expect(find.text('Use your location?'), findsNothing);
      gps.stream.add(WalkingLocationFix(origin, DateTime.now(), accuracy: 5));
      await settleIO();
      await t.tap(find.widgetWithText(NavigationDestination, 'CoolSpots'));
      await settleIO();
      expect(gps.stream.hasListener, true);
      const moved = Coordinates(latitude: 36.1905, longitude: -115.281);
      gps.stream.add(
        WalkingLocationFix(moved, DateTime.now(), accuracy: 5, speed: 1),
      );
      await settleIO();
      await t.tap(find.widgetWithText(NavigationDestination, 'ShadeMap'));
      await settleIO();
      expect(panel, findsOneWidget);
      await reveal(toggle);
      expect(find.text('Stop navigation'), findsOneWidget);
      expect(find.byType(PolylineLayer<int>), findsOneWidget);
      final map = t.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(moved.latitude, 1e-6),
      );
      expect(
        map.mapController!.camera.center.longitude,
        closeTo(moved.longitude, 1e-6),
      );
      await t.tap(toggle);
      await settleIO();
      expect(gps.stream.hasListener, false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      settings.dispose();
      service.client.close();
      await gps.stream.close();
    },
  );
}
