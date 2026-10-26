import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/demo/home_demo_data.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/presentation/home_dashboard.dart';
import 'package:heatwatch/features/heat_guard/presentation/home_header.dart';
import 'package:heatwatch/features/heat_guard/presentation/weather_overview.dart';

import 'daily_recommendations_test.dart' show recommendationFixture;

void main() {
  final now = DateTime.utc(2026, 7, 10, 20);
  const place = WeatherPlace.savedArea;
  Future<FreeWeatherResult> data({bool warning = false}) async =>
      FreeWeatherResult(
        place: place,
        weather: await HomeDemoWeather(now).fetch(place),
        alerts: await HomeDemoAlerts(now, warning: warning).fetch(place),
        weatherError: null,
        alertError: null,
      );
  Future<void> load(
    WidgetTester tester,
    FreeWeatherResult? result, {
    double scale = 1,
    VoidCallback? shade,
    VoidCallback? cool,
    AppSettings? settings,
  }) async {
    final app = MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeDashboard(
              result: result,
              place: place,
              now: now,
              loading: false,
              onRefresh: () {},
              onLocation: () {},
              onShade: shade,
              onCool: cool,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      settings == null ? app : SettingsScope(settings: settings, child: app),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone layout switches forecast and expands UV, actions work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var shade = 0, cool = 0;
    await load(tester, await data(), shade: () => shade++, cool: () => cool++);
    expect(find.text('104°F'), findsWidgets);
    await tester.tap(find.text('Hourly'));
    await tester.pumpAndSettle();
    expect(find.text('Hourly Forecast'), findsOneWidget);
    await tester.ensureVisible(find.text('UV details'));
    await tester.tap(find.text('UV details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UV details').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Low 0–2'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('home-uv-card'))))
        .pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open ShadeMap'));
    await tester.tap(find.text('Open ShadeMap'));
    await tester.pump();
    expect(shade, 1);
    await tester.ensureVisible(find.text('Find Cool Spots'));
    await tester.tap(find.text('Find Cool Spots'));
    await tester.pump();
    expect(cool, 1);
    expect(tester.takeException(), null);
  });
  for (final width in [320.0, 390.0, 768.0, 1200.0]) {
    testWidgets('large text, reduced motion and missing data at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await load(tester, null, scale: 2);
      expect(find.textContaining('min ago'), findsNothing);
      expect(find.text('Open-Meteo · CC BY 4.0'), findsNothing);
      await tester.ensureVisible(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.textContaining('Weather unavailable'), findsOneWidget);
    });
  }
  testWidgets('sticky header keeps temperature while dashboard scrolls', (
    tester,
  ) async {
    final overview = WeatherOverview()..update(place, await data(), false);
    await tester.pumpWidget(
      WeatherOverviewScope(
        overview: overview,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const HomeHeaderLocation(),
              actions: [HomeHeaderTemperature(clock: () => now)],
            ),
            body: ListView(
              children: [
                HomeDashboard(
                  result: overview.result,
                  place: place,
                  now: now,
                  loading: false,
                  onRefresh: () {},
                  onLocation: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final header = find.byKey(const ValueKey('persistent-temperature'));
    final before = tester.getTopLeft(header);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), before);
    expect(tester.widget<Text>(header).data, '104°F');
    await tester.pumpWidget(const SizedBox());
    overview.dispose();
  });
  testWidgets(
    'active warning expands and keeps issuer, dates and instructions',
    (tester) async {
      await load(tester, await data(warning: true));
      final warning = find.widgetWithText(
        ExpansionTile,
        'Extreme Heat Warning',
      );
      await tester.ensureVisible(warning);
      await tester.tap(warning);
      await tester.pumpAndSettle();
      expect(find.text('Issuer: Simulated NWS issuer'), findsOneWidget);
      expect(find.textContaining('Expires: 2026-07-10'), findsOneWidget);
      expect(find.textContaining('Demo action text'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 768.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'tailored four-card advice stays readable at $width / text $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final alerts = await HomeDemoAlerts(now, warning: true).fetch(place);
          await load(
            tester,
            recommendationFixture(
              fahrenheit: 110,
              uv: 13,
              windMph: 40,
              code: 95,
              alerts: alerts,
            ),
            scale: scale,
          );
          for (final id in [
            'nws-active',
            'conditions-storm',
            'thermal-105-114',
            'uv-extreme',
          ]) {
            final card = find.byKey(ValueKey('recommendation-$id'));
            expect(card, findsOneWidget);
            await tester.ensureVisible(card);
            await tester.pumpAndSettle();
            for (final text in tester.widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )) {
              expect(
                text.maxLines,
                isNull,
                reason: 'Advice must not be truncated',
              );
              expect(text.overflow, isNot(TextOverflow.ellipsis));
            }
          }
          expect(find.text('Minimize outdoor exposure'), findsOneWidget);
          expect(find.text('UV 13.0 · Extreme'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'recommendation units follow settings and linked actions still work',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      addTearDown(settings.dispose);
      await settings.load();
      await settings.update(useImperial: false);
      var cool = 0, shade = 0;
      await load(
        tester,
        recommendationFixture(fahrenheit: 110, windMph: 20, uv: 13),
        settings: settings,
        cool: () => cool++,
        shade: () => shade++,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recommendation-thermal-105-114')),
          matching: find.text('43°C'),
        ),
        findsOneWidget,
      );
      expect(find.text('Wind 32 km/h'), findsOneWidget);
      final cooling = find.byKey(
        const ValueKey('recommendation-thermal-105-114'),
      );
      await tester.ensureVisible(cooling);
      await tester.tap(cooling);
      final sun = find.byKey(const ValueKey('recommendation-uv-extreme'));
      await tester.ensureVisible(sun);
      await tester.tap(sun);
      expect(cool, 1);
      expect(shade, 1);
      expect(tester.takeException(), null);
    },
  );
}
