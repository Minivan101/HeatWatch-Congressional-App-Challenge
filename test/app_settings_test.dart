import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/settings/settings_sheet.dart';
import 'package:heatwatch/core/widgets/data_status.dart';

void main() {
  test('preferences restore, convert real zero and preserve unknown', () async {
    String? saved;
    final settings = AppSettings(
      read: () async => saved,
      write: (s) async => saved = s,
    );
    await settings.update(theme: ThemeMode.dark, useFahrenheit: true);
    final restored = AppSettings(read: () async => saved, write: (_) async {});
    await restored.load();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.temperature(0), '32.0°F');
    expect(restored.temperature(null), 'unavailable');
    await restored.update(useFahrenheit: false);
    expect(restored.temperature(35), '35.0°C');
    expect(restored.distance(1609.344), '1.6 km');
    expect(restored.windSpeed(16.09344), '16 km/h');
    await restored.update(useImperial: true);
    expect(restored.temperature(35), '95.0°F');
    expect(restored.distance(1609.344), '1.0 mi');
    expect(restored.windSpeed(16.09344), '10 mph');
    expect(restored.radius(5), '5 miles');
    expect(
      restored.walkingInstruction('In 100 m, turn left'),
      'In 330 ft, turn left',
    );
  });
  test(
    'route preference and first-use prompt persist independently of GPS',
    () async {
      String? saved;
      final settings = AppSettings(
        read: () async => saved,
        write: (s) async => saved = s,
      );
      await settings.update(
        preference: RoutePreference.mostShade,
        preferencePromptSeen: true,
        location: LocationChoice.never,
        useFahrenheit: true,
      );
      await settings.update(theme: ThemeMode.dark);
      final restored = AppSettings(
        read: () async => saved,
        write: (_) async {},
      );
      await restored.load();
      expect(restored.routePreference, RoutePreference.mostShade);
      expect(restored.routePreferencePromptSeen, true);
      expect(restored.locationChoice, LocationChoice.never);
      expect(restored.fahrenheit, true);
    },
  );
  test('old or unknown route preferences default safely', () async {
    for (final json in [
      '{"location":"never"}',
      '{"routePreference":"invalid"}',
    ]) {
      final settings = AppSettings(read: () async => json, write: (_) async {});
      await settings.load();
      expect(settings.routePreference, RoutePreference.balanced);
      expect(settings.routePreferencePromptSeen, false);
    }
  });
  test('delayed restoration cannot overwrite a user choice', () async {
    final pending = Completer<String?>();
    final settings = AppSettings(
      read: () => pending.future,
      write: (_) async {},
    );
    final loading = settings.load();
    await settings.update(theme: ThemeMode.light);
    pending.complete('{"theme":"dark","fahrenheit":true}');
    await loading;
    expect(settings.themeMode, ThemeMode.light);
    expect(settings.fahrenheit, true);
  });
  test('corrupt preferences and save failure keep session usable', () async {
    final settings = AppSettings(
      read: () async => 'invalid',
      write: (_) async => throw StateError('disk unavailable'),
    );
    await settings.load();
    expect(settings.themeMode, ThemeMode.system);
    await settings.update(useFahrenheit: true);
    expect(settings.temperature(35), '95.0°F');
    expect(settings.saveError, isNotNull);
  });
  testWidgets(
    'settings and retry states fit small dark screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: SettingsSheet(settings: settings)),
        ),
      );
      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(settings.themeMode, ThemeMode.dark);
      await tester.ensureVisible(find.text('Imperial · °F, mi'));
      await tester.tap(find.text('Imperial · °F, mi'));
      await tester.pump();
      expect(settings.fahrenheit, true);
      expect(tester.takeException(), isNull);
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataStatus(
              message: 'Check incomplete. Current status unverified.',
              failed: true,
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Retry check'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
