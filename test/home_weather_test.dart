import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/demo/home_demo_data.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/models/home_weather.dart';
import 'package:heatwatch/features/heat_guard/models/uv_level.dart';
import 'package:heatwatch/features/heat_guard/services/alert_lifecycle.dart';

void main() {
  const place = WeatherPlace.savedArea;
  final now = DateTime.utc(2026, 7, 10, 20);
  Future<WeatherReading> reading(DateTime at) =>
      HomeDemoWeather(at).fetch(place);
  test('solar phases use returned solar instants, including sunset twilight and night', () async {
    final w = await reading(now);
    expect(
      solarPhase(w, DateTime.utc(2026, 7, 10, 12, 30)),
      SolarPhase.sunrise,
    );
    expect(solarPhase(w, now), SolarPhase.midday);
    expect(solarPhase(w, DateTime.utc(2026, 7, 11, 3)), SolarPhase.sunset);
    expect(solarPhase(w, DateTime.utc(2026, 7, 11, 6)), SolarPhase.night);
    expect(solarPhase(null, now), SolarPhase.unknown);
  });
  test(
    'selected IANA timezone handles both DST offsets, independent of device',
    () async {
      final w = await reading(now), time = PlaceTime(await reading(now));
      expect(time.local(DateTime.utc(2026, 11, 1, 8, 30)).hour, 1);
      expect(time.local(DateTime.utc(2026, 11, 1, 9, 30)).hour, 1);
      expect(
        time.local(DateTime.utc(2026, 11, 1, 8, 30)).timeZoneOffset.inHours,
        -7,
      );
      expect(
        time.local(DateTime.utc(2026, 11, 1, 9, 30)).timeZoneOffset.inHours,
        -8,
      );
      expect(PlaceTime(w).date(DateTime.utc(2026, 7, 11, 6)), '2026-07-10');
    },
  );
  test(
    'dayparts mean all period hours, retain precision, hide passed periods',
    () async {
      final w = await reading(now), parts = dayparts(await reading(now), now);
      expect(parts.map((p) => p.label), ['Afternoon', 'Evening', 'Late night']);
      final samples = w.hourlyConditions
          .where(
            (h) =>
                h.validAt.day == 10 &&
                h.validAt.hour >= 19 &&
                h.validAt.hour < 24,
          )
          .toList();
      expect(
        parts.first.averageC,
        samples.fold<double>(0, (v, h) => v + h.temperatureC!) / 5,
      );
      expect(parts.first.current, true);
      expect(parts.where((p) => p.warmest).length, 1);
      expect(
        dayparts(w, DateTime.utc(2026, 7, 11, 6)).single.label,
        'Late night',
      );
    },
  );
  test(
    'UV remains current hourly at night while daily peak stays separately high',
    () async {
      final at = DateTime.utc(2026, 7, 11, 6),
          w = await reading(DateTime.utc(2026, 7, 11, 6));
      expect(w.uvFor(at)?.value, 0);
      expect(w.dailyUv.first.maximum, 10);
      expect(UvLevel.fromValue(w.uvFor(at)?.value), UvLevel.low);
      expect(UvLevel.fromValue(15), UvLevel.extreme);
      expect(UvLevel.fromValue(null), null);
      expect(UvLevel.fromValue(double.nan), null);
    },
  );
  test('routine heat recommendations prioritize the active alert with three unique cards', () async {
    final w = await reading(now),
        a = await HomeDemoAlerts(now, warning: true).fetch(place);
    final result = FreeWeatherResult(
      place: place,
      weather: w,
      alerts: a,
      weatherError: null,
      alertError: null,
    );
    final r = recommendations(result, now);
    expect(r.length, 3);
    expect(r.first.category, 'official');
    expect(r.map((r) => r.category).toSet().length, 3);
    expect(
      r.every((r) => r.source.startsWith('https://') && r.ruleId.isNotEmpty),
      true,
    );
    expect(activeAlerts(a, now.add(const Duration(hours: 7))), isEmpty);
  });
  test(
    'stale or failed temperature never triggers current heat advice',
    () async {
      final w = await HomeDemoWeather(now, stale: true).fetch(place);
      final result = FreeWeatherResult(
        place: place,
        weather: w,
        alerts: null,
        weatherError: null,
        alertError: 'Unavailable',
      );
      expect(recommendations(result, now), isEmpty);
      expect(recommendations(null, now), isEmpty);
    },
  );
  test(
    'mild fresh conditions avoid generic hot weather recommendations',
    () async {
      final w = await HomeDemoWeather(now, mild: true).fetch(place);
      final r = recommendations(
        FreeWeatherResult(
          place: place,
          weather: w,
          alerts: null,
          weatherError: null,
          alertError: null,
        ),
        now,
      );
      expect(
        r.any((r) => r.category == 'cooling' || r.category == 'hydration'),
        false,
      );
      expect(r.map((r) => r.category), ['clothing', 'sun']);
      expect(r.first.title, 'Keep your outfit light');
    },
  );
}
