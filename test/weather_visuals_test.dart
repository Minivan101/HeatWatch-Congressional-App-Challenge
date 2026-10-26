import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/presentation/free_weather_preview.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';

import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

import 'package:heatwatch/features/heat_guard/presentation/weather_visuals.dart';
import 'package:heatwatch/features/heat_guard/presentation/uv_level_badge.dart';
import 'package:heatwatch/features/heat_guard/models/uv_level.dart';

void main() {
  testWidgets(
    'UV marker rises and changes color; extreme readings keep their true value',
    (tester) async {
      Future<void> mount(double? uv) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: UvGauge(value: uv)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(2);
      final lower = tester
          .widget<AnimatedPositioned>(
            find.byKey(const ValueKey('uv-gauge-marker')),
          )
          .top!;
      await mount(8);
      final higher = tester
          .widget<AnimatedPositioned>(
            find.byKey(const ValueKey('uv-gauge-marker')),
          )
          .top!;
      expect(higher, lessThan(lower));
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('uv-gauge-marker')),
          matching: find.byType(Container),
        ),
      );
      expect(
        (container.decoration as BoxDecoration).color,
        uvColors(UvLevel.veryHigh).$1,
      );
      await mount(14.5);
      expect(
        tester.widget<Semantics>(find.byType(Semantics).last).properties.value,
        '14.5, Extreme',
      );
      expect(
        tester
            .widget<AnimatedPositioned>(
              find.byKey(const ValueKey('uv-gauge-marker')),
            )
            .top,
        UvGauge.inset - 17,
      );
    },
  );
  testWidgets('unavailable UV has no low marker', (tester) async {
    for (final uv in [null, -1.0, double.nan]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UvGauge(value: uv)),
        ),
      );
      expect(find.byKey(const ValueKey('uv-gauge-marker')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.value == 'Unavailable',
        ),
        findsOneWidget,
      );
    }
  });
  testWidgets('circle and gauge fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                children: [
                  CurrentWeatherCircle(temperature: '113.0°F'),
                  Row(
                    children: [
                      UvGauge(value: 8),
                      Expanded(child: Text('Very high UV')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('113.0°F'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'complete weather report keeps details and advice at large text sizes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.utc(2026, 10, 2, 18, 30);
      final repository = WeatherRepository(
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: AlertsFake((p) async => alertReading(p, now, [])),
        cache: WeatherCache(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FreeWeatherPreview(
                repository: repository,
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check free weather & alerts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check free weather & alerts'));
      await tester.pumpAndSettle();
      expect(find.byType(WeatherSummaryHeader), findsOneWidget);
      expect(find.byType(UvGauge), findsNothing);
      expect(find.text('UV index'), findsOneWidget);
      expect(find.text('UV index for now'), findsNothing);
      expect(find.text('Daily Timeline'), findsNothing);
      expect(find.byKey(const ValueKey('uv-guidance-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('uv-advice-section')), findsOneWidget);
      expect(find.text('Weather details'), findsOneWidget);
      expect(find.text('UV details'), findsOneWidget);
      expect(find.textContaining('Water:'), findsOneWidget);
      expect(find.textContaining('Clothing:'), findsOneWidget);
      await tester.ensureVisible(find.text('UV details'));
      await tester.tap(find.text('UV details'));
      await tester.pumpAndSettle();
      expect(find.byType(UvGauge), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
