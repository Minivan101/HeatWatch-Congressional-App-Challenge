import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/presentation/free_weather_preview.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';

import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, alertReading;

void main() {
  for (final variant in [
    (390.0, 1.0, Brightness.light),
    (390.0, 1.0, Brightness.dark),
    (320.0, 2.0, Brightness.dark),
  ]) {
    final (width, scale, brightness) = variant;
    testWidgets(
      'reference header and full-width UV at $width/$scale/$brightness',
      (tester) async {
        tester.view.physicalSize = Size(width, 650);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.utc(2026, 10, 6, 19);
        final weather = WeatherFake(
          (place) async => WeatherReading(
            place: place,
            gridPoint: place.coordinates,
            fetchedAt: now,
            currentValidAt: now,
            temperatureC: 35,
            feelsLikeC: 36,
            humidityPercent: 20,
            hourlyUv: [TimedUv(now, 14.5)],
            dailyUv: [],
            timezone: 'America/Los_Angeles',
            utcOffsetSeconds: -25200,
            issues: [],
          ),
        );
        final alerts = AlertsFake(
          (place) async => alertReading(place, now, []),
        );
        final repository = WeatherRepository(
          weather: weather,
          alerts: alerts,
          cache: WeatherCache(),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('HeatWatch')),
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FreeWeatherPreview(
                    repository: repository,
                    autoStart: true,
                    clock: () => now,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final weatherRect = tester.getRect(
          find.byKey(const ValueKey('weather-summary')),
        );
        final uvRect = tester.getRect(find.byKey(const ValueKey('uv-summary')));
        expect(weatherRect.width, greaterThan(width - 50));
        expect(uvRect.width, closeTo(weatherRect.width, 1));
        expect(uvRect.top, greaterThan(weatherRect.bottom));
        if (scale == 1) {
          final placeRect = tester.getRect(
            find.text('Saved Las Vegas map area'),
          );
          final temperatureRect = tester.getRect(
            find.byKey(const ValueKey('weather-current-temperature')),
          );
          expect(placeRect.right, lessThan(temperatureRect.left));
          expect(uvRect.bottom, lessThan(570));
          expect(find.text('14.5').hitTestable(), findsOneWidget);
          expect(find.text('Extreme UV').hitTestable(), findsOneWidget);
        }
        expect(find.text('14.5'), findsOneWidget);
        expect(find.text('Daily Timeline'), findsNothing);
        expect(find.text('Sunny'), findsNothing);
        expect(weather.calls, 1);
        expect(alerts.calls, 1);
        await tester.ensureVisible(find.text('Weather details'));
        await tester.tap(find.text('Weather details'));
        await tester.pumpAndSettle();
        expect(find.text('Open-Meteo · CC BY 4.0'), findsOneWidget);
        await tester.ensureVisible(find.text('UV details'));
        await tester.tap(find.text('UV details'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Forecast hour: 10/6/2026'), findsOneWidget);
        expect(weather.calls, 1);
        expect(alerts.calls, 1);
        expect(tester.takeException(), null);
      },
    );
  }
}
