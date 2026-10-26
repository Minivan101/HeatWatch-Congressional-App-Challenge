import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/presentation/free_weather_preview.dart';
import 'package:heatwatch/features/heat_guard/presentation/weather_overview.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';

import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

void main() {
  testWidgets(
    'pinned temperature shares auto-start data and refreshes across tabs, pauses in background',
    (tester) async {
      var now = DateTime.now().toUtc();
      final weather = WeatherFake((p) async => readingAt(p, now));
      final alerts = AlertsFake((p) async => alertReading(p, now, []));
      final repository = WeatherRepository(
        weather: weather,
        alerts: alerts,
        cache: WeatherCache(),
        clock: () => now,
      );
      final overview = WeatherOverview();
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await settings.update(useFahrenheit: false);
      await tester.pumpWidget(
        SettingsScope(
          settings: settings,
          child: WeatherOverviewScope(
            overview: overview,
            child: MaterialApp(
              home: Scaffold(
                appBar: AppBar(
                  title: const Text('HeatWatch'),
                  actions: [CurrentTemperatureDisplay(clock: () => now)],
                ),
                body: SingleChildScrollView(
                  child: FreeWeatherPreview(
                    repository: repository,
                    clock: () => now,
                    active: false,
                    autoStart: true,
                    keepOverviewUpdated: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      String header() => tester
          .widget<Text>(find.byKey(const ValueKey('persistent-temperature')))
          .data!;
      String hero() => tester
          .widget<Text>(
            find.byKey(const ValueKey('weather-current-temperature')),
          )
          .data!;
      expect(header(), '35.0°C');
      expect(header(), hero());
      expect(weather.calls, 1);
      expect(alerts.calls, 1);
      await settings.update(useFahrenheit: true);
      await tester.pumpAndSettle();
      expect(header(), '95.0°F');
      expect(header(), hero());
      now = now.add(const Duration(minutes: 16));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(weather.calls, 2);
      expect(alerts.calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 40));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(weather.calls, 2);
      expect(alerts.calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(weather.calls, 3);
      expect(alerts.calls, 3);
      await tester.pumpWidget(const SizedBox());
      overview.dispose();
    },
  );
  testWidgets('pinned temperature shows missing and saved readings honestly', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final overview = WeatherOverview();
    await tester.pumpWidget(
      WeatherOverviewScope(
        overview: overview,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [CurrentTemperatureDisplay(clock: () => now)],
            ),
          ),
        ),
      ),
    );
    final header = find.byKey(const ValueKey('persistent-temperature'));
    expect(tester.widget<Text>(header).data, '—°C');
    const place = WeatherPlace.savedArea;
    overview.update(
      place,
      FreeWeatherResult(
        place: place,
        weather: readingAt(place, now.subtract(const Duration(minutes: 40))),
        alerts: null,
        weatherError: 'Offline',
        alertError: null,
      ),
      false,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(header).data, '35.0°C');
    expect(find.text('Saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    overview.dispose();
  });
}
