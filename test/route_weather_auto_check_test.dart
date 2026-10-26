import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/presentation/route_weather_panel.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';

import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

void main() {
  testWidgets(
    'route calculation starts free UV/weather checks once; later duration changes reuse forecasts',
    (tester) async {
      final now = DateTime.utc(2026, 10, 2, 18, 30);
      var weatherCalls = 0, alertCalls = 0;
      final repository = WeatherRepository(
        clock: () => now,
        weather: WeatherFake((p) async {
          weatherCalls++;
          return readingAt(p, now);
        }),
        alerts: AlertsFake((p) async {
          alertCalls++;
          return alertReading(p, now, []);
        }),
        cache: WeatherCache(),
      );
      Future<void> mount(
        bool autoCheck, {
        bool active = true,
        int minutes = 30,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RouteWeatherPanel(
                  destination: const CoolingDestination(
                    id: 'public-test',
                    name: 'Public test place',
                    address: '',
                    location: Coordinates(latitude: 36.21, longitude: -115.27),
                    sourceUrl: 'https://example.com/test-only',
                    precision: 'test-only',
                  ),
                  origin: const Coordinates(
                    latitude: 36.19,
                    longitude: -115.28,
                  ),
                  repository: repository,
                  clock: () => now,
                  plannedDeparture: now,
                  routeDuration: Duration(minutes: minutes),
                  active: active,
                  autoCheck: autoCheck,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(false);
      expect(weatherCalls, 0);
      expect(alertCalls, 0);
      await mount(true, active: false);
      expect(weatherCalls, 0);
      await mount(true);
      expect(weatherCalls, 2);
      expect(alertCalls, 2);
      expect(find.textContaining('UV 5.3'), findsWidgets);
      await mount(true, minutes: 45);
      expect(weatherCalls, 2);
      expect(alertCalls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
