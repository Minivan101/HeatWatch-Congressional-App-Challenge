import 'dart:math' as math;

import '../models/free_weather.dart';
import '../services/free_weather_providers.dart';

class HomeDemoWeather implements WeatherProvider {
  HomeDemoWeather(
    this.now, {
    this.unavailable = false,
    this.stale = false,
    this.mild = false,
  });
  final DateTime now;
  final bool unavailable, stale, mild;
  @override
  Future<WeatherReading> fetch(WeatherPlace place) async {
    if (unavailable) throw StateError('Simulated provider outage');
    final midnight = DateTime.utc(2026, 7, 10, 7);
    final t = mild ? 24.0 : 40.0;
    final hour = (now.hour + 17) % 24;
    final current = mild
        ? t
        : hour < 9
        ? t - 10
        : hour >= 20
        ? t - 4
        : t;
    return WeatherReading(
      place: place,
      gridPoint: place.coordinates,
      fetchedAt: stale ? now.subtract(const Duration(hours: 2)) : now,
      currentValidAt: stale ? now.subtract(const Duration(hours: 2)) : now,
      temperatureC: current,
      feelsLikeC: current + 1,
      humidityPercent: 18,
      weatherCode: 0,
      isDay:
          now.isAfter(midnight.add(const Duration(hours: 6))) &&
          now.isBefore(midnight.add(const Duration(hours: 20))),
      windKmh: 12,
      timezone: 'America/Los_Angeles',
      utcOffsetSeconds: -25200,
      issues: [],
      hourlyUv: [
        for (var i = 0; i < 48; i++)
          TimedUv(
            midnight.add(Duration(hours: i)),
            i % 24 < 6 || i % 24 >= 20
                ? 0
                : math.max(0, 10.0 - (i % 24 - 13).abs() * 1.4),
          ),
      ],
      hourlyConditions: [
        for (var i = 0; i < 48; i++)
          TimedConditions(
            midnight.add(Duration(hours: i)),
            t - 7 + 7 * math.sin((i % 24 - 8) * math.pi / 16),
            t,
            18,
            weatherCode: i % 24 >= 6 && i % 24 < 20 ? 0 : 1,
          ),
      ],
      dailyUv: const [DailyUv('2026-07-10', 10), DailyUv('2026-07-11', 10)],
      dailyConditions: [
        for (var i = 0; i < 2; i++)
          DailyConditions(
            '2026-07-${10 + i}',
            highC: t,
            lowC: t - 10,
            sunrise: midnight.add(Duration(days: i, hours: 5, minutes: 30)),
            sunset: midnight.add(Duration(days: i, hours: 20)),
          ),
      ],
    );
  }
}

class HomeDemoAlerts implements AlertProvider {
  HomeDemoAlerts(this.now, {this.warning = false, this.unavailable = false});
  final DateTime now;
  final bool warning, unavailable;
  @override
  Future<AlertReading> fetch(WeatherPlace place) async {
    if (unavailable) throw StateError('Simulated alert outage');
    return AlertReading(
      place: place,
      fetchedAt: now,
      providerUpdatedAt: now,
      alerts: warning
          ? [
              NwsAlert(
                id: 'simulated-heat-warning',
                sourceUrl: Uri.parse('https://www.weather.gov/vef/'),
                event: 'Extreme Heat Warning',
                headline: 'SIMULATED DEMO: Extreme Heat Warning',
                description: 'SIMULATED DEMO DATA. This is a fictional warning for layout review, not a current NWS alert.',
                instruction: 'Demo action text: postpone strenuous outdoor activity and use an air-conditioned space.',
                senderName: 'Simulated NWS issuer',
                severity: 'Severe',
                status: 'Actual',
                messageType: 'Alert',
                sent: now.subtract(const Duration(hours: 1)),
                effective: now.subtract(const Duration(hours: 1)),
                onset: now.subtract(const Duration(hours: 1)),
                expires: now.add(const Duration(hours: 6)),
                ends: null,
                raw: const {
                  'properties': {'areaDesc': 'Simulated Las Vegas area'},
                },
              ),
            ]
          : [],
    );
  }
}
