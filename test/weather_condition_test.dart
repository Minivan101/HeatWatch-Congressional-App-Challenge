import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/models/weather_condition.dart';
import 'package:heatwatch/features/heat_guard/presentation/weather_visuals.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';

void main() {
  Map<String, dynamic> fixture() => jsonDecode(
    File('test/fixtures/weather/open_meteo_recorded.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  WeatherReading parse(Map<String, dynamic> raw) => OpenMeteoProvider.parse(
    raw,
    place: WeatherPlace.savedArea,
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      (raw['current']['time'] as int) * 1000,
      isUtc: true,
    ),
  );
  test('request includes condition and day/night, while legacy cache stays unknown', () {
    expect(
      OpenMeteoProvider.requestFor(WeatherPlace.savedArea)
          .queryParameters['current'],
      contains('weather_code,is_day'),
    );
    final old = parse(fixture());
    expect(old.condition.sky, WeatherSky.unknown);
    expect(old.temperatureC, isNotNull);
    expect(old.isDay, isNull);
  });
  test('strict WMO fields survive parsing; invalid units, codes and times stay unknown', () {
    final raw = fixture();
    raw['current_units'].addAll({'weather_code': 'wmo code', 'is_day': ''});
    raw['current'].addAll({'weather_code': 63, 'is_day': 0});
    expect(parse(raw).condition.sky, WeatherSky.rain);
    expect(parse(raw).isDay, false);
    for (final code in [4, 63.5, -1, 100, null, '63']) {
      raw['current']['weather_code'] = code;
      expect(parse(raw).condition.sky, WeatherSky.unknown);
    }
    raw['current']['weather_code'] = 0;
    raw['current']['is_day'] = 2;
    expect(parse(raw).isDay, null);
    raw['current_units']['weather_code'] = 'wrong';
    expect(parse(raw).weatherCode, null);
    raw['current_units']['weather_code'] = 'wmo code';
    raw['current_units']['time'] = 'iso8601';
    expect(parse(raw).weatherCode, null);
  });
  testWidgets(
    'condition icons distinguish clear day, clear night, clouds and rain',
    (tester) async {
      for (final variant in [
        (0, true, CupertinoIcons.sun_max_fill, 'Clear'),
        (0, false, CupertinoIcons.moon_stars_fill, 'Clear'),
        (2, true, CupertinoIcons.cloud_sun_fill, 'Partly cloudy'),
        (2, false, CupertinoIcons.cloud_moon_fill, 'Partly cloudy'),
        (63, true, CupertinoIcons.cloud_rain_fill, 'Rain'),
        (95, true, CupertinoIcons.cloud_bolt_rain_fill, 'Thunderstorm'),
        (999, true, Icons.help_outline, 'Weather'),
      ]) {
        final (code, day, icon, label) = variant;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WeatherSummaryHeader(
                place: 'Las Vegas',
                temperature: '32°C',
                feelsLike: '34°C',
                humidity: '20%',
                condition: WeatherCondition.fromCode(code, isDay: day),
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<Icon>(
                find.byKey(const ValueKey('weather-condition-icon')),
              )
              .icon,
          icon,
        );
        expect(find.text(label), findsOneWidget);
        expect(find.text('32°C'), findsOneWidget);
        expect(find.byIcon(Icons.thermostat_outlined), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
