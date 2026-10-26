import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/heat_guard/presentation/free_weather_preview.dart';
import 'package:heatwatch/features/heat_guard/presentation/route_weather_panel.dart';

import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading, alertRecord;

void main() {
  final initial = DateTime.utc(2026, 10, 2, 18, 30);
  Future<void> reveal(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'foreground refresh starts with explicit check and pauses on hidden tab/background',
    (tester) async {
      var now = initial;
      final w = WeatherFake((p) async => readingAt(p, now));
      final a = AlertsFake((p) async => alertReading(p, now, []));
      final repo = WeatherRepository(
        weather: w,
        alerts: a,
        cache: WeatherCache(),
        clock: () => now,
      );
      Future<void> mount(bool active) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FreeWeatherPreview(
                repository: repo,
                clock: () => now,
                active: active,
              ),
            ),
          ),
        ),
      );
      await mount(true);
      await tester.pumpAndSettle();
      expect(w.calls, 0);
      expect(a.calls, 0);
      await reveal(tester, 'Check free weather & alerts');
      await tester.tap(find.text('Check free weather & alerts'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 6));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(w.calls, 1);
      expect(a.calls, 2);
      await mount(false);
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 1));
      expect(w.calls, 1);
      expect(a.calls, 2);
      await mount(true);
      await tester.pumpAndSettle();
      expect(w.calls, 2);
      expect(a.calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 1));
      expect(w.calls, 2);
      expect(a.calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(w.calls, 3);
      expect(a.calls, 4);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'main official warning precedes modeled weather; report keeps instructions on $platform',
      (tester) async {
        var now = initial;
        final repo = WeatherRepository(
          weather: WeatherFake((p) async => readingAt(p, now)),
          alerts: AlertsFake(
            (p) async =>
                alertReading(p, now, [alertRecord('official-test-fixture')]),
          ),
          cache: WeatherCache(),
          clock: () => now,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: SingleChildScrollView(
                child: FreeWeatherPreview(repository: repo, clock: () => now),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await reveal(tester, 'Check free weather & alerts');
        await tester.tap(find.text('Check free weather & alerts'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Fictional test only: heat advisory')).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('weather-current-temperature')),
                )
                .dy,
          ),
        );
        expect(find.text('NWS · Severe · 1 active alert'), findsOneWidget);
        await reveal(tester, 'Alert details');
        await tester.tap(find.text('Alert details'));
        await tester.pumpAndSettle();

        final tile = find.byWidgetPredicate(
          (w) =>
              w is ExpansionTile &&
              w.title is Text &&
              (w.title as Text).data == 'Fictional test only: heat advisory',
        );
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(
          find.text('Fictional instructions, not a real warning.'),
          findsOneWidget,
        );
        await reveal(tester, 'Weather details');
        await tester.tap(find.text('Weather details'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Forecast time zone: Pacific Time (ID: America/Los_Angeles)',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Open-Meteo · CC BY 4.0'), findsOneWidget);
        expect(find.text('General preparation — HeatWatch'), findsNothing);
        expect(tester.takeException(), null);
      },
    );
  }

  testWidgets('restored offline values show age and no current all-clear', (
    tester,
  ) async {
    var now = initial;
    final cache = WeatherCache();
    final seed = WeatherRepository(
      weather: WeatherFake((p) async => readingAt(p, now)),
      alerts: AlertsFake((p) async => alertReading(p, now, [])),
      cache: cache,
      clock: () => now,
    );
    await seed.refresh(WeatherPlace.savedArea);
    now = now.add(const Duration(minutes: 40));
    final w = WeatherFake((p) async => throw StateError('offline'));
    final a = AlertsFake((p) async => throw StateError('offline'));
    final repo = WeatherRepository(
      weather: w,
      alerts: a,
      cache: cache,
      clock: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FreeWeatherPreview(repository: repo, clock: () => now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(w.calls, 0);
    expect(a.calls, 0);
    expect(find.text('Saved weather · 40 min ago'), findsOneWidget);
    expect(
      find.text('Official alert check is outdated. Check again.'),
      findsOneWidget,
    );
    expect(
      find.text('No active alerts returned by NWS for this point.'),
      findsNothing,
    );
    await reveal(tester, 'Choose location and time');
    await tester.tap(find.text('Choose location and time'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Clear saved weather and alerts');
    await tester.tap(find.text('Clear saved weather and alerts'));
    await tester.pumpAndSettle();
    expect(await cache.read(), null);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('weather-current-temperature')),
          )
          .data,
      '—',
    );
  });

  testWidgets(
    'scheduled departure remains fixed across later checks; leave now follows the clock',
    (tester) async {
      var now = initial;
      const destination = CoolingDestination(
        id: 'timing-test',
        name: 'Timing fixture',
        address: 'Fixture',
        location: Coordinates(latitude: 36.2, longitude: -115.2),
        sourceUrl: 'https://example.com/source',
        precision: 'Fixture',
      );
      final repo = WeatherRepository(
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: AlertsFake((p) async => alertReading(p, now, [])),
        cache: WeatherCache(),
        clock: () => now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteWeatherPanel(
                destination: destination,
                repository: repo,
                clock: () => now,
                active: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'Change departure and walking time');
      await tester.tap(find.text('Change departure and walking time'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Leave in 1 h');
      await tester.tap(find.text('Leave in 1 h'));
      await tester.pumpAndSettle();
      final scheduled = tester
          .widget<Text>(find.textContaining('Depart '))
          .data;
      now = now.add(const Duration(minutes: 10));
      await reveal(tester, 'Check departure & arrival weather');
      await tester.tap(find.text('Check departure & arrival weather'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('Depart ')).data,
        scheduled,
      );
      await reveal(tester, 'Leave now');
      await tester.tap(find.text('Leave now'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('Depart ')).data,
        isNot(scheduled),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'route uses two real selected points and user-planned duration, no shade cooling claim',
    (tester) async {
      const destination = CoolingDestination(
        id: 'real-fixture',
        name: 'Source location fixture',
        address: 'Fixture only',
        location: Coordinates(latitude: 36.2, longitude: -115.2),
        sourceUrl: 'https://example.com/source',
        precision: 'Source test point',
      );
      final points = <String>[];
      final repo = WeatherRepository(
        weather: WeatherFake((p) async {
          points.add(WeatherRepository.pointKey(p));
          return readingAt(p, initial);
        }),
        alerts: AlertsFake((p) async => alertReading(p, initial, [])),
        cache: WeatherCache(),
        clock: () => initial,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteWeatherPanel(
                destination: destination,
                repository: repo,
                clock: () => initial,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(points, isEmpty);
      expect(find.textContaining('not a calculated ETA'), findsOneWidget);
      await reveal(tester, 'Check departure & arrival weather');
      await tester.tap(find.text('Check departure & arrival weather'));
      await tester.pumpAndSettle();
      expect(points.toSet(), {'36.19531,-115.28587', '36.2,-115.2'});
      expect(find.text('Your trip'), findsOneWidget);
      expect(find.text('Building shade: not calculated'), findsOneWidget);
      expect(find.textContaining('Departure forecast'), findsNothing);
      await reveal(tester, 'Trip details and sources');
      await tester.tap(find.text('Trip details and sources'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Departure forecast'), findsOneWidget);
      expect(find.textContaining('Arrival forecast'), findsOneWidget);

      expect(find.textContaining('Modeled 35.0°C'), findsNWidgets(2));
      await reveal(tester, 'Change departure and walking time');
      await tester.tap(find.text('Change departure and walking time'));
      await tester.pumpAndSettle();
      await reveal(tester, '60 min');
      await tester.tap(find.text('60 min'));
      await tester.pumpAndSettle();
      expect(points.length, 2);
      await reveal(tester, 'Check departure & arrival weather');
      await tester.tap(find.text('Check departure & arrival weather'));
      await tester.pumpAndSettle();
      expect(points.length, 2);
      expect(
        find.text('Saved forecast; see retrieval age below.'),
        findsNWidgets(2),
      );
      expect(find.text('Saved alert check'), findsNWidgets(2));
    },
  );
}
