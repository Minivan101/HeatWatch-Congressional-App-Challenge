import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/models/weather_condition.dart';
import 'package:heatwatch/features/shade_route/services/route_weather_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 11, 19);
  WeatherReading reading({required DateTime fetchedAt, int currentCode = 0}) =>
      WeatherReading(
        place: const WeatherPlace(
          label: 'Las Vegas',
          coordinates: Coordinates(latitude: 36.19, longitude: -115.28),
        ),
        gridPoint: const Coordinates(latitude: 36.19, longitude: -115.28),
        fetchedAt: fetchedAt,
        currentValidAt: fetchedAt,
        temperatureC: 35,
        feelsLikeC: 37,
        humidityPercent: 12,
        hourlyUv: const [],
        dailyUv: const [],
        timezone: 'America/Los_Angeles',
        utcOffsetSeconds: -25200,
        issues: const [],
        weatherCode: currentCode,
        hourlyConditions: [
          TimedConditions(
            now.add(const Duration(hours: 3)),
            34,
            36,
            12,
            weatherCode: 3,
          ),
        ],
      );

  test('current clear weather keeps shade choices distinct', () {
    final condition = routeConditionAt(reading(fetchedAt: now), now, now);
    expect(condition?.sky, WeatherSky.clear);
    expect(cloudsMakeShadeComparisonIrrelevant(condition), false);
  });

  test(
    'scheduled walks use clear-sky shade even with an overcast forecast',
    () {
      final condition = routeConditionAt(
        reading(fetchedAt: now),
        now.add(const Duration(hours: 3, minutes: 15)),
        now,
      );
      expect(condition, isNull);
      expect(cloudsMakeShadeComparisonIrrelevant(condition), false);
      expect(
        routeConditionAt(
          reading(fetchedAt: now, currentCode: 3),
          now.add(const Duration(minutes: 30)),
          now,
        ),
        isNull,
      );
    },
  );

  test('stale weather never suppresses the shade comparison', () {
    final condition = routeConditionAt(
      reading(
        fetchedAt: now.subtract(const Duration(hours: 2)),
        currentCode: 3,
      ),
      now,
      now,
    );
    expect(condition, isNull);
    expect(cloudsMakeShadeComparisonIrrelevant(condition), false);
  });
}
