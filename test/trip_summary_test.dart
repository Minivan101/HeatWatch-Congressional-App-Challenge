import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/presentation/trip_summary_content.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';

import 'weather_repository_test.dart' show alertReading, alertRecord;
import 'free_weather_providers_test.dart' show weatherFixture;

void main() {
  final now = DateTime.utc(2026, 10, 2, 18, 30);
  const place = WeatherPlace.savedArea;
  FreeWeatherResult result({
    List<Object> alerts = const [],
    bool saved = false,
    String? error,
    DateTime? checked,
  }) => FreeWeatherResult(
    place: place,
    weather: null,
    alerts: alertReading(place, checked ?? now, alerts),
    weatherError: null,
    alertError: error,
    alertsFromCache: saved,
  );
  Future<void> mount(
    WidgetTester tester,
    FreeWeatherResult? start,
    FreeWeatherResult? end,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TripSummaryContent(
          start: start,
          end: end,
          departure: now,
          arrival: now.add(const Duration(minutes: 30)),
          now: now,
        ),
      ),
    ),
  );

  testWidgets(
    'partial failed or saved checks never become a trip-wide all-clear',
    (tester) async {
      await mount(tester, result(), null);
      expect(find.text('Alerts not checked'), findsOneWidget);
      await mount(tester, result(), result(error: 'offline'));
      expect(find.text('Alerts not checked'), findsOneWidget);
      await mount(tester, result(), result(saved: true));
      expect(find.text('Alerts not checked'), findsOneWidget);
      await mount(
        tester,
        result(),
        result(checked: now.subtract(const Duration(minutes: 6))),
      );
      expect(find.text('Alerts not checked'), findsOneWidget);
      await mount(tester, result(), result());
      expect(
        find.text('No currently effective alerts returned at either point'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'duplicate warning counts once; severe warning stays first and saved status stays visible',
    (tester) async {
      final minor = alertRecord('minor', severity: 'Minor');
      final extreme = alertRecord('extreme', severity: 'Extreme');
      (extreme['properties'] as Map)['event'] = 'Excessive Heat Warning';
      await mount(
        tester,
        result(alerts: [minor, extreme]),
        result(alerts: [extreme], saved: true),
      );
      expect(find.text('Excessive Heat Warning · 2 alerts'), findsOneWidget);
      expect(find.text('Saved alert check'), findsOneWidget);
      expect(
        find.text('No currently effective alerts returned at either point'),
        findsNothing,
      );
    },
  );
  testWidgets('expired records are not promoted to active warnings', (
    tester,
  ) async {
    final expired = alertRecord('old', expires: '2026-10-02T18:00:00Z');
    await mount(tester, result(alerts: [expired]), result());
    expect(find.text('Heat Advisory'), findsNothing);
    expect(
      find.text('No currently effective alerts returned at either point'),
      findsOneWidget,
    );
  });
  testWidgets(
    'numeric UV zero survives; absent temperature and missing arrival hour stay unknown',
    (tester) async {
      final raw = weatherFixture();
      raw['hourly']['uv_index'] = List.filled(
        (raw['hourly']['time'] as List).length,
        0,
      );
      final weather = OpenMeteoProvider.parse(
        raw,
        place: place,
        fetchedAt: now,
      );
      final r = FreeWeatherResult(
        place: place,
        weather: weather,
        alerts: null,
        weatherError: null,
        alertError: null,
      );
      await mount(tester, r, null);
      expect(find.textContaining('UV 0.0'), findsOneWidget);
      expect(find.textContaining('UV unknown'), findsOneWidget);
      expect(find.text('Building shade: not calculated'), findsOneWidget);
    },
  );
}
