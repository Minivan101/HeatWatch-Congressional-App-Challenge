import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:heatwatch/app.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/settings/settings_sheet.dart';
import 'package:heatwatch/core/settings/settings_store_file.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native settings persist in isolated storage and apply to the app',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'heatwatch-settings-check-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = SettingsStore(directory: directory);
      final preferences = AppSettings(read: store.read, write: store.write);
      await preferences.load();
      await preferences.update(location: LocationChoice.never);
      final weather = WeatherRepository(cache: WeatherCache());
      await tester.pumpWidget(
        HeatWatchApp(
          settings: preferences,
          promptLocation: false,
          weatherRepository: weather,
        ),
      );
      await tester.pumpAndSettle();
      if (find.text('Use your location?').evaluate().isNotEmpty) {
        await tester.tap(find.text('Never'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.tap(find.text('Fahrenheit (°F)'));
      await tester.pumpAndSettle();
      final settings = tester
          .widget<SettingsSheet>(find.byType(SettingsSheet))
          .settings;

      await settings.update(theme: ThemeMode.dark, useFahrenheit: true);
      final restored = AppSettings(read: store.read, write: store.write);
      await restored.load();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.fahrenheit, true);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byTooltip('Settings'))).brightness,
        Brightness.dark,
      );
      await tester.pumpWidget(
        HeatWatchApp(
          key: const ValueKey("restored-settings-check"),
          settings: restored,
          promptLocation: false,
          weatherRepository: weather,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byTooltip('Settings'))).brightness,
        Brightness.dark,
      );
      expect(restored.temperature(0), '32.0°F');

      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
