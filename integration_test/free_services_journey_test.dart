import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/presentation/route_weather_panel.dart';
import 'package:integration_test/integration_test.dart';

import 'package:heatwatch/app.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/core/settings/app_settings.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
  await tester.pumpAndSettle();
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 160; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Expected visible result: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'official cooling destination and free weather connect across tabs',
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
      await tester.tap(find.text('Never'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.ac_unit));
      await waitFor(tester, find.text('Showing 5 of 19 locations'));
      await tester.enterText(find.byType(TextField), 'Meadows Library');
      await tester.pumpAndSettle();
      expect(find.text('1 location shown'), findsOneWidget);
      expect(find.text('Officially listed cooling locations'), findsOneWidget);
      await reveal(tester, find.byTooltip('Details & sources').first);
      await tester.tap(find.byTooltip('Details & sources').first);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Meadows Library',
        ),
        findsOneWidget,
      );
      await reveal(tester, find.text('Select as planned destination'));
      await tester.tap(find.text('Select as planned destination'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('route-destination-field')),
          matching: find.text('Meadows Library'),
        ),
        findsOneWidget,
      );
      await reveal(tester, find.text('Coordinates & intermediate points'));
      await tester.tap(find.text('Coordinates & intermediate points'));
      await tester.pumpAndSettle();
      final startField = find.widgetWithText(
        TextField,
        'Start latitude, longitude',
      );
      await reveal(tester, startField);
      await tester.enterText(startField, '36.19531, -115.28587');
      await reveal(tester, find.text('Use coordinates'));
      await tester.tap(find.text('Use coordinates'));
      await tester.pumpAndSettle();
      expect(find.text('Shade route choices (demo)'), findsNothing);

      await reveal(tester, find.text('Trip weather'));
      await tester.tap(find.text('Trip weather'));
      await tester.pumpAndSettle();
      final check = find.text('Check departure & arrival weather');
      await reveal(tester, check);
      final panel = tester.widget<RouteWeatherPanel>(
        find.byType(RouteWeatherPanel),
      );
      expect(panel.destination.name, 'Meadows Library');
      expect(panel.routeDuration, isNull);
      await tester.tap(check);
      await reveal(tester, find.text('Trip details and sources'));
      await tester.tap(find.text('Trip details and sources'));
      await waitFor(tester, find.textContaining('Arrival forecast'));
      final end = WeatherPlace(
        label: panel.destination.name,
        coordinates: panel.destination.location,
      );
      final startResult = await panel.repository.cachedFor(
        WeatherPlace.savedArea,
      );
      final endResult = await panel.repository.cachedFor(end);
      expect(startResult?.weather, isNotNull);
      expect(endResult?.weather, isNotNull);
      expect(startResult?.weatherError, isNull);
      expect(endResult?.weatherError, isNull);
      expect(startResult?.alerts, isNotNull);
      expect(endResult?.alerts, isNotNull);
      expect(startResult?.alertError, isNull);
      expect(endResult?.alertError, isNull);
      final departure = DateTime.now().toUtc();
      expect(endResult!.weather!.conditionsFor(departure), isNotNull);
      expect(endResult.weather!.uvFor(departure), isNotNull);
      await reveal(tester, find.textContaining('Arrival forecast'));
      expect(find.textContaining('not a calculated ETA'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.health_and_safety));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Choose location and time'));
      await tester.tap(find.text('Choose location and time'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Planned destination'));
      await tester.tap(find.text('Planned destination'));
      await waitFor(tester, find.text('Meadows Library'));
      await reveal(tester, find.text('Check free weather & alerts'));
      await tester.tap(find.text('Check free weather & alerts'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('weather-current-temperature')),
            )
            .data,
        isNot('—'),
      );
      expect(
        find.textContaining(RegExp(r'^(Updated|Saved weather) ·')),
        findsOneWidget,
      );
      await reveal(tester, find.text('Weather details'));
      final details = find.text('Weather details');
      final controller = ExpansibleController.of(tester.element(details));
      if (!controller.isExpanded) {
        await tester.tap(details.hitTestable());
        await tester.pumpAndSettle();
      }
      expect(controller.isExpanded, isTrue);
      expect(find.text('Open-Meteo · CC BY 4.0'), findsOneWidget);
      await reveal(tester, find.text('Open-Meteo · CC BY 4.0'));
      expect(find.text('Open-Meteo · CC BY 4.0'), findsOneWidget);
      await reveal(tester, find.text('Alert details'));
      await tester.tap(find.text('Alert details'));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('NWS checked:'));
      expect(find.textContaining('NWS checked:'), findsOneWidget);
    },
  );
}
