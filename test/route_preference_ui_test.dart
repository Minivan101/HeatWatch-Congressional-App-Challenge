import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/shade_route/presentation/city_trip_panel.dart';

import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/presentation/shade_street_map.dart';

import 'city_trip_map_test.dart' show MapService, LiveMapPosition, origin, end;
import 'shared_location_test.dart' show TestPosition;
import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

class RouteCountService extends MapService {
  RouteCountService(this.count);
  final int count;
  @override
  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async =>
      (await super.walkAlternatives(start, end, via: via)).take(count).toList();
}

class NearlySameService extends MapService {
  @override
  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async {
    final routes = await super.walkAlternatives(start, end, via: via);
    final first = routes.first;
    return [
      first,
      CityWalkingRoute(
        WalkingGeometry(
          points: [
            start,
            Coordinates(
              latitude: first.geometry.points[1].latitude + .00002,
              longitude: first.geometry.points[1].longitude,
            ),
            end,
          ],
          durationSeconds: 360,
          sourceUrl: 'test-only',
          accessReviewed: false,
        ),
        600,
      ),
    ];
  }
}

class ThreeRoutesService extends MapService {
  @override
  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async {
    final routes = await super.walkAlternatives(start, end, via: via);
    return [
      ...routes,
      CityWalkingRoute(
        WalkingGeometry(
          points: [
            start,
            Coordinates(
              latitude: start.latitude + .003,
              longitude: start.longitude,
            ),
            end,
          ],
          durationSeconds: 480,
          sourceUrl: 'test-only',
          accessReviewed: false,
        ),
        800,
      ),
    ];
  }
}

void main({bool native = false}) {
  bool selectedChoice(WidgetTester tester, RoutePreference preference) => tester
      .widgetList<Icon>(
        find.descendant(
          of: find.byKey(ValueKey('route-preference-${preference.name}')),
          matching: find.byType(Icon),
        ),
      )
      .any((icon) => icon.icon == Icons.check_circle);

  Future<AppLocation> mount(
    WidgetTester tester,
    AppSettings settings,
    MapService service, {
    ValueNotifier<bool>? active,
    LiveMapPosition? gps,
    bool lowShade = false,
    bool night = false,
    bool missingShade = false,
    Brightness brightness = Brightness.light,
  }) async {
    if (!native) {
      tester.view.physicalSize = const Size(420, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await settings.load();
    final location = AppLocation(settings, service: gps ?? TestPosition());
    await location.choose(LocationChoice.session);
    final now = DateTime.now().toUtc();
    final weather = WeatherRepository(
      weather: WeatherFake((p) async => readingAt(p, now)),
      alerts: AlertsFake((p) async => alertReading(p, now, [])),
      cache: WeatherCache(),
    );
    Widget panel(bool isActive) => CityTripPanel(
      service: service,
      tilesEnabled: false,
      weather: weather,
      active: isActive,
      destination: const CoolingDestination(
        id: 'test-only',
        name: 'Public test fixture',
        address: '',
        location: end,
        sourceUrl: 'https://example.com/test-only',
        precision: 'test-only',
      ),
      shadeCalculator: (route, _) async => {
        'shade': night || missingShade
            ? null
            : lowShade
            ? .05
            : (route.distanceMeters == 500 ? .1 : .8),
        'coverage': night || missingShade ? null : 1.0,
        'night': night ? route.distanceMeters : 0.0,
        'distance': route.distanceMeters,
      },
    );
    await tester.pumpWidget(
      SettingsScope(
        settings: settings,
        child: LocationScope(
          location: location,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: active == null
                  ? panel(true)
                  : ValueListenableBuilder<bool>(
                      valueListenable: active,
                      builder: (_, value, _) => panel(value),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() {
      location.dispose();
      service.client.close();
      settings.dispose();
    });
    return location;
  }

  testWidgets(
    'almost identical shade and fastest winners merge into one actual fastest walk',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await mount(tester, settings, NearlySameService());
      final card = find.byKey(const ValueKey('best-route-choice'));
      expect(card, findsOneWidget);
      expect(
        tester
            .widget<ShadeStreetMap>(find.byType(ShadeStreetMap))
            .routes
            .single
            .geometry
            .durationSeconds,
        300,
      );
      expect(
        find.descendant(of: card, matching: find.text('5 min')),
        findsOneWidget,
      );
      expect(find.text('Most shade'), findsNothing);
      expect(find.text('Fastest route'), findsNothing);
      expect(find.text('Balanced'), findsNothing);
    },
  );
  testWidgets(
    'three genuine candidates still expose only the two distinct winners',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await mount(tester, settings, ThreeRoutesService());
      expect(find.text('Most shade'), findsOneWidget);
      expect(find.text('Fastest route'), findsOneWidget);
      expect(find.text('Best route'), findsNothing);
      expect(find.text('Balanced'), findsNothing);
    },
  );
  for (final count in [1, 2]) {
    testWidgets(
      '$count candidate cards retain readable contrast in dark mode',
      (tester) async {
        final settings = AppSettings(
          read: () async => null,
          write: (_) async {},
        );
        await mount(
          tester,
          settings,
          RouteCountService(count),
          brightness: Brightness.dark,
        );
        final cards = count == 1
            ? [find.byKey(const ValueKey('best-route-choice'))]
            : [
                find.byKey(const ValueKey('route-preference-mostShade')),
                find.byKey(const ValueKey('route-preference-fastest')),
              ];
        for (final card in cards) {
          final background = tester
              .element(card)
              .findAncestorWidgetOfExactType<Material>()!
              .color!;
          for (final node
              in find
                  .descendant(of: card, matching: find.byType(Text))
                  .evaluate()) {
            final text = node.widget as Text;
            final color =
                text.style?.color ?? DefaultTextStyle.of(node).style.color!;
            final a = color.computeLuminance(),
                b = background.computeLuminance();
            final contrast =
                (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
            expect(
              contrast,
              greaterThanOrEqualTo(4.5),
              reason: 'Unreadable card text: ${text.data}',
            );
          }
        }
      },
    );
  }

  for (final count in [1, 2]) {
    for (final unknown in [false, true]) {
      testWidgets(
        '$count genuine candidates have correct cards; unknown=$unknown',
        (tester) async {
          final settings = AppSettings(
            read: () async => null,
            write: (_) async {},
          );
          await mount(
            tester,
            settings,
            RouteCountService(count),
            missingShade: unknown,
          );
          expect(
            find.text('Best route'),
            count == 1 || unknown ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('best-route-choice')),
            count == 1 || unknown ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Most shade'),
            count == 2 && !unknown ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Fastest route'),
            count == 2 && !unknown ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('route-preference-balanced')),
            findsNothing,
          );
          expect(find.textContaining('%'), findsNothing);
        },
      );
    }
  }

  for (final night in [true, false]) {
    testWidgets(
      night
          ? 'night walking shows after sunset and selects fastest'
          : 'missing shade keeps walking routes without a main-screen warning',
      (tester) async {
        final settings = AppSettings(
          read: () async => null,
          write: (_) async {},
        );
        await settings.load();
        await settings.update(
          preference: RoutePreference.mostShade,
          preferencePromptSeen: true,
        );
        await mount(
          tester,
          settings,
          MapService(),
          night: night,
          missingShade: !night,
        );
        expect(find.text('Best route'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('route-preference-fastest')),
          findsNothing,
        );
        expect(
          find.textContaining('Shade comparison unavailable'),
          findsNothing,
        );
        expect(find.textContaining('Shade: data unavailable'), findsNothing);
        expect(find.textContaining('%'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'both route choices reroute from current GPS without stopping tracking',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await settings.load();
      await settings.update(preferencePromptSeen: true);
      final gps = LiveMapPosition();
      final service = MapService();
      final location = await mount(tester, settings, service, gps: gps);
      final scroll = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      final start = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(start, 100, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      const moved = Coordinates(latitude: 36.1901, longitude: -115.2802);
      gps.stream.add(
        WalkingLocationFix(
          moved,
          DateTime.now(),
          accuracy: 5,
          heading: 90,
          speed: 1,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Fastest route', 'Most shade']) {
        final choice = find.text(label);
        await tester.scrollUntilVisible(choice, -100, scrollable: scroll);
        await tester.pumpAndSettle();
        final before = service.walks;
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(service.walks, before + 1);
        expect(service.usedStart?.latitude, moved.latitude);
        expect(location.tracking, true);
        expect(gps.stream.hasListener, true);
        expect(find.textContaining('%'), findsNothing);

        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(service.walks, before + 1);
        expect(location.tracking, true);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await gps.stream.close();
    },
  );

  testWidgets(
    'equal shade combines into the fastest Best route without percentages',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await settings.load();
      await settings.update(
        preference: RoutePreference.mostShade,
        preferencePromptSeen: true,
      );
      await mount(tester, settings, MapService(), lowShade: true);
      expect(find.text('Best route'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(settings.routePreference, RoutePreference.mostShade);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route choices appear without a modal and remember the selected option',
    (tester) async {
      String? saved;
      final settings = AppSettings(
        read: () async => saved,
        write: (s) async => saved = s,
      );
      final service = MapService();
      await mount(tester, settings, service);
      expect(find.byType(AlertDialog), findsNothing);
      expect(selectedChoice(tester, RoutePreference.mostShade), true);
      await tester.tap(find.byKey(const ValueKey('route-preference-fastest')));
      await tester.pumpAndSettle();
      expect(selectedChoice(tester, RoutePreference.fastest), true);
      await tester.tap(
        find.byKey(const ValueKey('route-preference-mostShade')),
      );
      await tester.pumpAndSettle();
      expect(selectedChoice(tester, RoutePreference.mostShade), true);
      expect(service.walks, 1);
      expect(service.usedStart?.latitude, origin.latitude);
      final restored = AppSettings(
        read: () async => saved,
        write: (_) async {},
      );
      await restored.load();
      expect(restored.routePreference, RoutePreference.mostShade);
      expect(restored.routePreferencePromptSeen, true);
      await tester.pumpWidget(const SizedBox());
      final next = MapService();
      await mount(tester, restored, next);
      expect(
        find.byKey(const ValueKey('first-route-preference')),
        findsNothing,
      );
      expect(selectedChoice(tester, RoutePreference.mostShade), true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('legacy Balanced restores a visible shade choice across tabs', (
    tester,
  ) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final service = MapService();
    await mount(tester, settings, service, active: active);
    expect(find.byType(AlertDialog), findsNothing);
    expect(settings.routePreferencePromptSeen, false);
    active.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(selectedChoice(tester, RoutePreference.mostShade), true);
    active.value = false;
    await tester.pumpAndSettle();
    active.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(settings.routePreferencePromptSeen, false);
    expect(settings.routePreference, RoutePreference.balanced);
    expect(service.walks, 1);
    expect(tester.takeException(), isNull);
  });
}
