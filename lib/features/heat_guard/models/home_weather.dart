import 'dart:math' as math;

import 'package:timezone/data/latest.dart' as database;
import 'package:timezone/timezone.dart' as tz;

import 'free_weather.dart';
import 'uv_level.dart';
export 'daily_recommendations.dart' show HomeRecommendation, recommendations;

class PlaceTime {
  PlaceTime(WeatherReading? reading) : offset = reading?.utcOffsetSeconds ?? 0 {
    if (!_initialized) {
      database.initializeTimeZones();
      _initialized = true;
    }
    try {
      zone = tz.getLocation(reading?.timezone ?? 'America/Los_Angeles');
    } catch (_) {
      zone = null;
    }
  }
  static bool _initialized = false;
  final int offset;
  tz.Location? zone;
  DateTime local(DateTime at) => zone == null
      ? at.toUtc().add(Duration(seconds: offset))
      : tz.TZDateTime.from(at, zone!);
  String date(DateTime at) => local(at).toIso8601String().substring(0, 10);
  String hour(DateTime at) {
    final v = local(at), h = v.hour;
    return '${h % 12 == 0 ? 12 : h % 12}${v.minute == 0 ? '' : ':${v.minute.toString().padLeft(2, '0')}'} ${h < 12 ? 'AM' : 'PM'}';
  }
}

enum SolarPhase { sunrise, morning, midday, afternoon, sunset, night, unknown }

SolarPhase solarPhase(WeatherReading? reading, DateTime now) {
  if (reading == null) return SolarPhase.unknown;
  final daily = todayConditions(reading, now);
  final rise = daily?.sunrise, set = daily?.sunset;
  if (rise == null || set == null) return SolarPhase.unknown;
  const edge = Duration(minutes: 30);
  if (now.isBefore(rise.subtract(edge)) || !now.isBefore(set.add(edge))) {
    return SolarPhase.night;
  }
  if (now.isBefore(rise.add(edge))) return SolarPhase.sunrise;
  if (!now.isBefore(set.subtract(edge))) return SolarPhase.sunset;
  final daylight = set.difference(rise).inMinutes;
  final elapsed = now.difference(rise).inMinutes;

  if (elapsed < daylight / 3) return SolarPhase.morning;
  if (elapsed < daylight * 2 / 3) return SolarPhase.midday;
  return SolarPhase.afternoon;
}

DailyConditions? todayConditions(WeatherReading reading, DateTime now) {
  final date = PlaceTime(reading).date(now);
  for (final day in reading.dailyConditions) {
    if (day.localDate == date) return day;
  }
  return null;
}

class DaypartForecast {
  const DaypartForecast(
    this.label,
    this.averageC,
    this.hours,
    this.current,
    this.warmest,
  );
  final String label;
  final double averageC;
  final List<TimedConditions> hours;
  final bool current, warmest;
}

List<DaypartForecast> dayparts(WeatherReading reading, DateTime now) {
  final time = PlaceTime(reading), today = PlaceTime(reading).date(now);
  const periods = [
    ('Overnight', 0, 5),
    ('Early morning', 5, 9),
    ('Late morning', 9, 12),
    ('Afternoon', 12, 17),
    ('Evening', 17, 21),
    ('Late night', 21, 24),
  ];
  final groups = <(String, double, List<TimedConditions>, bool)>[];
  for (final p in periods) {
    if (time.local(now).hour >= p.$3) continue;
    final samples = reading.hourlyConditions.where((h) {
      final at = time.local(h.validAt);
      return time.date(h.validAt) == today && at.hour >= p.$2 && at.hour < p.$3;
    }).toList();

    final local = time.local(now);
    final expected = time.zone == null
        ? p.$3 - p.$2
        : tz.TZDateTime(time.zone!, local.year, local.month, local.day, p.$3)
              .difference(
                tz.TZDateTime(
                  time.zone!,
                  local.year,
                  local.month,
                  local.day,
                  p.$2,
                ),
              )
              .inHours;
    if (samples.length != expected ||
        samples.any((h) => h.temperatureC == null)) {
      continue;
    }
    final mean =
        samples.fold<double>(0, (v, h) => v + h.temperatureC!) / samples.length;
    groups.add((p.$1, mean, samples, time.local(now).hour >= p.$2));
  }
  final maximum = groups.isEmpty
      ? null
      : groups.map((g) => g.$2).reduce(math.max);
  return groups
      .map((g) => DaypartForecast(g.$1, g.$2, g.$3, g.$4, g.$2 == maximum))
      .toList();
}

List<TimedConditions> upcomingHours(WeatherReading reading, DateTime now) =>
    reading.hourlyConditions
        .where(
          (h) =>
              h.validAt.add(const Duration(hours: 1)).isAfter(now) &&
              h.validAt.isBefore(now.add(const Duration(hours: 24))),
        )
        .take(24)
        .toList();
String forecastInsight(WeatherReading reading, DateTime now) {
  final samples = upcomingHours(
    reading,
    now,
  ).where((h) => h.temperatureC != null).toList();
  if (samples.isEmpty) return 'Hourly temperature forecast unavailable.';
  final peak = samples.reduce(
    (a, b) => a.temperatureC! >= b.temperatureC! ? a : b,
  );
  return 'Warmest forecast hour in the next 24 hours: ${PlaceTime(reading).hour(peak.validAt)}.';
}

String uvAdvice(UvLevel? level) => switch (level) {
  UvLevel.extreme =>
    'Reduce direct sun exposure. Choose shade and cover exposed skin.',
  UvLevel.veryHigh || UvLevel.high =>
    'Limit midday sun. Use shade, protective clothing and SPF 30+.',
  UvLevel.moderate =>
    'Seek midday shade. Use protective clothing and SPF 30+ outdoors.',
  UvLevel.low => 'Low UV now. Protection needs still vary; heat can persist.',
  null => 'UV unavailable. Check before a long outdoor outing.',
};
