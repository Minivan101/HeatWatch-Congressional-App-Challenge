import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/demo/home_demo_data.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/models/home_weather.dart';

const recommendationNow = '2026-07-10T20:00:00Z';
double celsius(double f) => (f - 32) * 5 / 9;

FreeWeatherResult recommendationFixture({
  double? fahrenheit = 72,
  double? apparentF,
  double? uv = 4,
  double? windMph = 0,
  double? humidity = 25,
  int? code = 0,
  bool? day = true,
  bool staleCurrent = false,
  bool staleForecast = false,
  bool failed = false,
  AlertReading? alerts,
}) {
  final now = DateTime.parse(recommendationNow);
  const place = WeatherPlace.savedArea;
  return FreeWeatherResult(
    place: place,
    weather: WeatherReading(
      place: place,
      gridPoint: place.coordinates,
      fetchedAt: staleForecast ? now.subtract(const Duration(hours: 2)) : now,
      currentValidAt: staleCurrent
          ? now.subtract(const Duration(hours: 2))
          : now,
      temperatureC: fahrenheit == null ? null : celsius(fahrenheit),
      feelsLikeC: apparentF == null ? null : celsius(apparentF),
      humidityPercent: humidity,
      windKmh: windMph == null ? null : windMph * 1.609344,
      weatherCode: code,
      isDay: day,
      hourlyUv: [TimedUv(now, uv)],
      dailyUv: const [DailyUv('2026-07-10', 13)],
      timezone: 'America/Los_Angeles',
      utcOffsetSeconds: -25200,
      issues: [],
    ),
    alerts: alerts,
    weatherError: failed ? 'provider unavailable' : null,
    alertError: null,
  );
}

List<HomeRecommendation> advice(
  FreeWeatherResult result, {
  bool imperial = true,
}) => recommendations(
  result,
  DateTime.parse(recommendationNow),
  imperial: imperial,
);

void main() {
  for (final sample in <(double, String)>[
    (31, 'freezing'),
    (32, 'freezing'),
    (32.1, '33-44'),
    (44.9, '33-44'),
    (45, '45-54'),
    (54.9, '45-54'),
    (55, '55-64'),
    (64.9, '55-64'),
    (65, '65-74'),
    (74.9, '65-74'),
    (75, '75-84'),
    (84.9, '75-84'),
    (85, '85-94'),
    (94.9, '85-94'),
    (95, '95-104'),
    (104.9, '95-104'),
    (105, '105-114'),
    (114.9, '105-114'),
    (115, '115-plus'),
    (120, '115-plus'),
  ]) {
    test(
      'outfit/heat boundary ${sample.$1} F chooses a single appropriate band',
      () {
        final r = advice(
          recommendationFixture(fahrenheit: sample.$1, uv: null),
        );
        expect(r.single.ruleId, 'thermal-${sample.$2}');
        expect(r.single.condition, contains('${sample.$1.round()}°F'));
        expect(
          advice(
            recommendationFixture(fahrenheit: sample.$1, uv: null),
            imperial: false,
          ).single.ruleId,
          r.single.ruleId,
        );
      },
    );
  }
  test(
    'feels-like cold selects a light jacket without changing measured weather',
    () {
      final r = advice(recommendationFixture(fahrenheit: 70, apparentF: 61));
      expect(r.first.title, 'Bring a light jacket');
      expect(r.first.condition, 'Feels like 61°F');
    },
  );
  test('dry apparent temperature cannot downgrade actual desert heat', () {
    final r = advice(
      recommendationFixture(fahrenheit: 108, apparentF: 99, humidity: 12),
    );
    expect(r.first.ruleId, 'thermal-105-114');
    expect(r.first.condition, '108°F · 12% humidity');
    expect(r.first.detail, contains('do not wait for thirst'));
  });
  test('hot humid feels-like reading increases cooling advice', () {
    final r = advice(
      recommendationFixture(fahrenheit: 90, apparentF: 102, humidity: 65),
    );
    expect(r.first.ruleId, 'thermal-95-104');
    expect(r.first.condition, 'Feels like 102°F · 65% humidity');
    expect(r.first.detail, contains('harder for sweat'));
    expect(r.first.action, 'cool');
  });
  for (final sample in <(double, String, String)>[
    (0, 'low', 'SPF 30+'),
    (2.9, 'low', 'SPF 30+'),
    (3, 'moderate', 'SPF 30+'),
    (5.9, 'moderate', 'SPF 30+'),
    (6, 'high', 'SPF 50+'),
    (7.9, 'high', 'SPF 50+'),
    (8, 'veryHigh', 'SPF 50+'),
    (10.9, 'veryHigh', 'SPF 50+'),
    (11, 'extreme', 'SPF 50+'),
    (13, 'extreme', 'SPF 50+'),
  ]) {
    test('current UV ${sample.$1} selects ${sample.$2} and supported SPF', () {
      final sun = advice(recommendationFixture(uv: sample.$1))
          .singleWhere((r) => r.category == 'sun');
      expect(sun.ruleId, 'uv-${sample.$2}');
      expect(sun.detail, contains(sample.$3));
      expect(sun.detail, contains('broad-spectrum'));
      expect(sun.detail, contains('every 2 hours'));
      expect(sun.detail, contains('sweating or swimming'));
    });
  }
  test(
    'UV 13 foregrounds exposure reduction, not a safe-minutes allowance',
    () {
      final sun = advice(recommendationFixture(uv: 13)).last;
      expect(sun.title, 'Minimize outdoor exposure');
      expect(sun.detail, contains('Move longer activities indoors'));
      expect(sun.detail, isNot(contains('minutes')));
    },
  );
  test(
    'temperature alone cannot increase SPF and low UV cannot excuse heat',
    () {
      final hot = advice(recommendationFixture(fahrenheit: 115, uv: 2));
      expect(hot.first.ruleId, 'thermal-115-plus');
      expect(hot.last.detail, contains('SPF 30+'));
      final cool = advice(recommendationFixture(fahrenheit: 58, uv: 13));
      expect(cool.first.ruleId, 'thermal-55-64');
      expect(cool.last.detail, contains('SPF 50+'));
    },
  );
  for (final sample in <(double, String?)>[
    (0, null),
    (11.9, null),
    (12, '12-19'),
    (19.9, '12-19'),
    (20, '20-29'),
    (29.9, '20-29'),
    (30, '30-39'),
    (39.9, '30-39'),
    (40, '40-plus'),
  ]) {
    test('wind ${sample.$1} mph adds only the matching wind precaution', () {
      final winds = advice(recommendationFixture(windMph: sample.$1))
          .where((r) => r.category == 'wind');
      if (sample.$2 == null) {
        expect(winds, isEmpty);
      } else {
        expect(winds.single.ruleId, 'wind-${sample.$2}');
      }
    });
  }
  test('metric advice converts condition labels, never thresholds or SPF', () {
    final r = advice(
      recommendationFixture(fahrenheit: 59, windMph: 20, uv: 8),
      imperial: false,
    );
    expect(r.singleWhere((r) => r.category == 'clothing').condition, '15°C');
    expect(
      r.singleWhere((r) => r.category == 'wind').condition,
      'Wind 32 km/h',
    );
    expect(r.last.detail, contains('SPF 50+'));
  });
  test('clouds never suppress UV-based protection', () {
    expect(
      advice(recommendationFixture(code: 3, uv: 8)).last.ruleId,
      'uv-veryHigh',
    );
  });
  test(
    'night retains heat precautions without daytime SPF advice or daily peak',
    () {
      final r = advice(
        recommendationFixture(fahrenheit: 105, day: false, uv: 0),
      );
      expect(r.single.ruleId, 'thermal-105-114');
      expect(
        advice(recommendationFixture(day: false, uv: 13))
            .any((r) => r.category == 'sun'),
        false,
      );
    },
  );
  test('missing daytime flag does not invent night or zero UV', () {
    expect(
      advice(recommendationFixture(day: null, uv: null))
          .any((r) => r.category == 'sun'),
      false,
    );
    expect(
      advice(recommendationFixture(day: null, uv: 2)).last.ruleId,
      'uv-low',
    );
  });
  test(
    'unknown temperature, humidity and wind never become normal conditions',
    () {
      final r = advice(
        recommendationFixture(
          fahrenheit: null,
          humidity: null,
          windMph: null,
          uv: null,
          code: null,
        ),
      );
      expect(r, isEmpty);
      expect(
        advice(recommendationFixture(fahrenheit: null, apparentF: 60, uv: null))
            .single
            .condition,
        'Feels like 60°F',
      );
    },
  );
  test('nonfinite and negative unsupported values never appear in advice', () {
    final r = advice(
      recommendationFixture(
        fahrenheit: double.nan,
        uv: -1,
        windMph: -5,
        humidity: double.infinity,
      ),
    );
    expect(r, isEmpty);
  });
  test(
    'stale current weather cannot trigger clothes, wind or rain; fresh UV can',
    () {
      final r = advice(
        recommendationFixture(
          fahrenheit: 115,
          windMph: 40,
          code: 95,
          staleCurrent: true,
        ),
      );
      expect(r.single.ruleId, 'uv-moderate');
      expect(advice(recommendationFixture(staleForecast: true)), isEmpty);
      expect(advice(recommendationFixture(failed: true)), isEmpty);
    },
  );
  for (final sample in <(int, String)>[
    (95, 'storm'),
    (99, 'storm'),
    (56, 'ice'),
    (67, 'ice'),
    (61, 'rain'),
    (82, 'rain'),
    (71, 'snow'),
    (45, 'fog'),
  ]) {
    test(
      'condition code ${sample.$1} provides specific local walking preparation',
      () {
        final r = advice(recommendationFixture(code: sample.$1));
        expect(r.first.ruleId, 'conditions-${sample.$2}');
        if (sample.$2 == 'storm') {
          expect(r.first.detail, contains('30 minutes'));
        }
        if (sample.$2 == 'rain') expect(r.first.detail, contains('washes'));
      },
    );
  }
  test(
    'multiple hazards retain alert, weather, heat and UV without duplicates',
    () async {
      final alerts = await HomeDemoAlerts(
        DateTime.parse(recommendationNow),
        warning: true,
      ).fetch(WeatherPlace.savedArea);
      final r = advice(
        recommendationFixture(
          fahrenheit: 110,
          uv: 13,
          code: 95,
          windMph: 40,
          alerts: alerts,
        ),
      );
      expect(r.map((r) => r.category), ['official', 'storm', 'cooling', 'sun']);
      expect(r.first.action, 'alert');
      expect(r[1].detail, contains('Strong wind'));
      expect(r.length, 4);
      expect(
        r.every((r) => r.source.startsWith('https://') && r.condition != null),
        true,
      );
      expect(
        advice(recommendationFixture(failed: true, alerts: alerts))
            .single
            .category,
        'official',
      );
    },
  );
}
