import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/app.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double step = 200,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      step,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var n = 0; n < 240; n++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Result did not appear: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'startup preference, safety, concise directory and real city walking trip',
    (tester) async {
      final preferences = AppSettings(
        read: () async => null,
        write: (_) async {},
      );
      await preferences.load();
      await preferences.update(
        location: LocationChoice.ask,
        preferencePromptSeen: true,
      );
      await tester.pumpWidget(
        HeatWatchApp(
          settings: preferences,
          weatherRepository: WeatherRepository(cache: WeatherCache()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use your location?'), findsOneWidget);
      expect(find.text('Every time I open the app'), findsOneWidget);
      await tester.tap(find.text('Never'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Off · manual planning'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Warnings & safety'));
      await tester.tap(find.text('Warnings & safety'));
      await tester.pumpAndSettle();
      expect(find.text('Plan with care'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.ac_unit));
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('Showing 5 of 19 locations'));
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Meadows');
      await tester.pumpAndSettle();
      await reveal(tester, find.byTooltip('Details & sources'));
      await tester.tap(find.byTooltip('Details & sources'));
      await tester.pumpAndSettle();
      expect(
        find.text('Distance: enable location in Settings'),
        findsOneWidget,
      );
      expect(find.text('Published hours'), findsOneWidget);
      expect(find.textContaining('Mon, Fri-Sat 10am-3pm'), findsOneWidget);
      expect(find.textContaining('published records'), findsOneWidget);
      expect(find.textContaining('opening unverified'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.route));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Coordinates & intermediate points'));
      await tester.tap(find.text('Coordinates & intermediate points'));
      await tester.pumpAndSettle();
      final start = find.widgetWithText(TextField, 'Start latitude, longitude');
      final end = find.widgetWithText(
        TextField,
        'Destination latitude, longitude',
      );
      await reveal(tester, start);
      await tester.enterText(start, '36.19143950472907, -115.30210200475739');
      await reveal(tester, end);
      await tester.enterText(end, '36.2174216443873, -115.25929184419876');
      await reveal(tester, find.text('Use coordinates'));
      await tester.tap(find.text('Use coordinates'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.text('Calculate walking route & shade'),
        step: -200,
      );
      await tester.tap(find.text('Calculate walking route & shade'));
      await waitFor(tester, find.textContaining('km walking'));

      for (var n = 0; n < 120; n++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await reveal(tester, find.textContaining('km walking').first);
      final walkingSummaries = tester.widgetList<Text>(
        find.textContaining('km walking'),
      );
      expect(walkingSummaries.length, inInclusiveRange(1, 3));
      for (final summary in walkingSummaries) {
        expect(summary.data, isNot(contains('Calculating')));
        expect(summary.data, isNot(contains('unavailable')));
      }
      await tester.tap(find.byIcon(Icons.health_and_safety));
      await tester.pumpAndSettle();
      expect(find.textContaining('Off · manual planning'), findsOneWidget);
      expect(find.textContaining('example'), findsNothing);
      await reveal(tester, find.text('Choose location and time'));
      await tester.tap(find.text('Choose location and time'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Planned destination'));
      await tester.tap(find.text('Planned destination'));
      await tester.pumpAndSettle();
      expect(find.text('Selected destination'), findsOneWidget);
      await reveal(tester, find.text('Check free weather & alerts'));
      await tester.tap(find.text('Check free weather & alerts'));
      for (var n = 0; n < 240; n++) {
        await tester.pump(const Duration(milliseconds: 250));
        final value = tester
            .widget<Text>(
              find.byKey(const ValueKey('weather-current-temperature')),
            )
            .data;
        if (value != '—') break;
      }
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('weather-current-temperature')),
            )
            .data,
        isNot('—'),
      );
      for (var n = 0; n < 240; n++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await reveal(tester, find.text('Weather details'));
      final detailControl = ExpansibleController.of(
        tester.element(find.text('Weather details')),
      );
      if (!detailControl.isExpanded) {
        await tester.tap(find.text('Weather details').hitTestable());
        await tester.pumpAndSettle();
      }
      expect(detailControl.isExpanded, isTrue);
      expect(find.text('Open-Meteo · CC BY 4.0'), findsOneWidget);
      await reveal(tester, find.text('UV details'));
      await tester.tap(find.text('UV details'));
      await tester.pumpAndSettle();
      expect(find.text('Daily UV outlook'), findsOneWidget);
      await reveal(tester, find.text('Alert details'));
      await tester.tap(find.text('Alert details'));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('NWS checked:'));
      expect(find.textContaining('NWS checked:'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await preferences.update(location: LocationChoice.ask);
    },
  );
}
