import 'package:heatwatch/core/settings/app_settings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/presentation/free_weather_preview.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';

class _Service extends FreeWeatherService {
  _Service(this.load);
  final Future<FreeWeatherResult> Function(WeatherPlace) load;
  @override
  Future<FreeWeatherResult> fetch(WeatherPlace place) => load(place);
}

class _DeniedLocation extends LocationService {
  @override
  Future<Coordinates> getCurrentPosition({bool requestPermission = true}) =>
      Future.error(const LocationAccessException(LocationProblem.denied));
}

void main() {
  final now = DateTime.utc(2026, 10, 2, 18, 30);
  FreeWeatherResult result(WeatherPlace place, {bool failedAlerts = false}) =>
      FreeWeatherResult(
        place: place,
        weather: WeatherReading(
          place: place,
          gridPoint: place.coordinates,
          fetchedAt: now,
          currentValidAt: now,
          temperatureC: 35,
          feelsLikeC: null,
          humidityPercent: null,
          hourlyUv: [TimedUv(DateTime.utc(2026, 10, 2, 18), null)],
          dailyUv: [const DailyUv('2026-10-02', 8)],
          timezone: 'America/Los_Angeles',
          utcOffsetSeconds: -25200,
          issues: ['Some hourly UV values unavailable or invalid.'],
        ),
        alerts: failedAlerts
            ? null
            : AlertReading(
                place: place,
                fetchedAt: now,
                providerUpdatedAt: null,
                alerts: [],
              ),
        weatherError: null,
        alertError: failedAlerts
            ? 'Official alerts could not be checked.'
            : null,
      );

  Future<void> mount(WidgetTester tester, FreeWeatherPreview preview) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: preview)),
        ),
      );
  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'no automatic request; partial live fields stay unknown on $platform',
      (tester) async {
        var calls = 0;
        final service = _Service((place) async {
          calls++;
          return result(place, failedAlerts: true);
        });
        final settings = AppSettings(
          read: () async => null,
          write: (_) async {},
        );
        await settings.update(useFahrenheit: false);
        await tester.pumpWidget(
          SettingsScope(
            settings: settings,
            child: MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: FreeWeatherPreview(service: service, clock: () => now),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(find.textContaining('Open-Meteo · NWS'), findsOneWidget);
        await tap(tester, 'Check free weather & alerts');
        expect(calls, 1);
        expect(find.text('35.0°C'), findsOneWidget);
        expect(find.text('UV unavailable'), findsOneWidget);
        expect(
          find.text('Official alerts could not be checked.'),
          findsOneWidget,
        );
        expect(find.textContaining('No active alerts'), findsNothing);
        expect(find.textContaining('Example temperature'), findsNothing);
        await tap(tester, 'Choose location and time');
        await settings.update(useFahrenheit: true);
        await tester.pumpAndSettle();
        expect(find.text('95.0°F'), findsOneWidget);
        expect(calls, 1);
        await tap(tester, 'UV details');
        await tap(tester, 'Daily UV outlook');
        expect(
          find.textContaining('Daily maximum UV 2026-10-02'),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
      },
    );
  }

  testWidgets('selecting a new point discards the in-flight old point result', (
    tester,
  ) async {
    final pending = Completer<FreeWeatherResult>();
    const destination = CoolingDestination(
      id: 'test-site',
      name: 'Test planned destination',
      address: 'Test only',
      location: Coordinates(latitude: 36.2, longitude: -115.2),
      sourceUrl: 'https://example.com/test',
      precision: 'Test fixture',
    );
    final service = _Service((_) => pending.future);
    await mount(
      tester,
      FreeWeatherPreview(
        service: service,
        destination: destination,
        clock: () => now,
      ),
    );
    await tester.ensureVisible(find.text('Check free weather & alerts'));
    await tester.pump();
    await tester.tap(find.text('Check free weather & alerts'));
    await tester.pump();

    await tester.ensureVisible(find.text('Choose location and time'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Choose location and time'));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Planned destination'));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Planned destination'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Planned destination'));
    await tester.pump(const Duration(seconds: 1));
    pending.complete(result(WeatherPlace.savedArea));
    await tester.pumpAndSettle();
    expect(find.text('Test planned destination'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('weather-current-temperature')),
          )
          .data,
      '—',
    );
  });

  testWidgets('denied location keeps the selectable area and does not fetch', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      FreeWeatherPreview(
        location: _DeniedLocation(),
        service: _Service((place) async {
          calls++;
          return result(place);
        }),
        clock: () => now,
      ),
    );
    await tap(tester, 'Choose location and time');
    await tap(tester, 'Use device location');
    expect(find.textContaining('Location access was denied'), findsOneWidget);
    expect(find.text('Saved Las Vegas map area'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('freshness labels age without an automatic provider request', (
    tester,
  ) async {
    var clock = now;
    var calls = 0;
    await mount(
      tester,
      FreeWeatherPreview(
        service: _Service((place) async {
          calls++;
          return result(place);
        }),
        clock: () => clock,
      ),
    );
    await tap(tester, 'Check free weather & alerts');
    expect(
      find.text('No active alerts returned by NWS for this point.'),
      findsOneWidget,
    );
    clock = now.add(const Duration(minutes: 31));
    await tester.pump(const Duration(minutes: 1));
    expect(
      find.text('Official alert check is outdated. Check again.'),
      findsOneWidget,
    );
    expect(find.text('Saved weather · 31 min ago'), findsOneWidget);
    expect(calls, 1);
  });
}
