import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:heatwatch/app.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/presentation/weather_overview.dart';

import 'city_planning_journey_test.dart' show reveal;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real free weather, pinned tabs, UV colors and section details in light and dark',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await settings.update(
        location: LocationChoice.never,
        theme: ThemeMode.light,
      );
      await tester.pumpWidget(
        HeatWatchApp(
          settings: settings,
          promptLocation: false,
          weatherRepository: WeatherRepository(cache: WeatherCache()),
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('persistent-temperature'));
      expect(header, findsOneWidget);
      await tester.tap(find.byIcon(Icons.health_and_safety));
      for (var n = 0; n < 240; n++) {
        await tester.pump(const Duration(milliseconds: 250));
        final value = tester.widget<Text>(header).data!;
        if (!value.startsWith('—') &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      final temperature = tester.widget<Text>(header).data!;
      expect(
        temperature.startsWith('—'),
        isFalse,
        reason: 'The real Open-Meteo current reading must arrive.',
      );
      final hero = find.byKey(const ValueKey('weather-current-temperature'));
      expect(tester.widget<Text>(hero).data, temperature);
      expect(
        find.byKey(const ValueKey('weather-condition-icon')),
        findsOneWidget,
      );
      expect(find.text('UV index'), findsOneWidget);
      for (final section in [
        'Weather details',
        'UV details',
        'Alert details',
      ]) {
        await reveal(tester, find.text(section));
        await tester.tap(find.text(section));
        await tester.pumpAndSettle();
      }
      expect(find.text('Open-Meteo · CC BY 4.0'), findsOneWidget);
      expect(find.text('Daily UV outlook'), findsOneWidget);
      expect(
        find.textContaining('NWS checked:'),
        findsOneWidget,
        reason: 'A real official alert check must succeed.',
      );

      for (final icon in [
        Icons.ac_unit,
        Icons.route,
        Icons.health_and_safety,
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(header).data, temperature);
      }
      await settings.update(theme: ThemeMode.dark, useFahrenheit: true);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(header).data!.endsWith('°F'), isTrue);
      expect(tester.widget<Text>(header).data, tester.widget<Text>(hero).data);
      expect(
        Theme.of(tester.element(find.byType(CurrentTemperatureDisplay)))
            .brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);

      for (final section in [
        'Weather details',
        'UV details',
        'Alert details',
      ]) {
        await reveal(tester, find.text(section));
        await tester.tap(find.text(section));
        await tester.pumpAndSettle();
      }
      await reveal(
        tester,
        find.byKey(const ValueKey('weather-condition-icon')),
      );
    },
  );
}
