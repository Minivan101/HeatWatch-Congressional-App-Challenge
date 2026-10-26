import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/shade_route/presentation/city_trip_panel.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';

import 'city_trip_map_test.dart' show MapService, LiveMapPosition, origin, end;
import 'weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

class Journey {
  Journey({this.now});
  final DateTime Function()? now;
  final gps = LiveMapPosition();
  final service = MapService();
  final settings = AppSettings(read: () async => null, write: (_) async {});
  late final location = AppLocation(settings, service: gps);
  Completer<void>? shadeGate;
  final toggle = find.byKey(const ValueKey('walking-navigation-toggle'));
  Finder get scroll => find
      .descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(WidgetTester t, Finder f, {double step = 100}) async {
    await t.scrollUntilVisible(f, step, scrollable: scroll);
    if (service.pending?.isCompleted != false &&
        shadeGate?.isCompleted != false) {
      await t.pumpAndSettle();
    } else {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 850);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await settings.load();
    await settings.update(
      preference: RoutePreference.fastest,
      preferencePromptSeen: true,
    );
    await location.choose(LocationChoice.session);
    final now = DateTime.now().toUtc();
    final weather = WeatherRepository(
      weather: WeatherFake((p) async => readingAt(p, now)),
      alerts: AlertsFake((p) async => alertReading(p, now, [])),
      cache: WeatherCache(),
    );
    await t.pumpWidget(
      SettingsScope(
        settings: settings,
        child: LocationScope(
          location: location,
          child: MaterialApp(
            home: Scaffold(
              body: CityTripPanel(
                service: service,
                weather: weather,
                tilesEnabled: false,
                now: this.now,
                destination: const CoolingDestination(
                  id: 'controlled',
                  name: 'Vegas test endpoint',
                  address: '',
                  location: end,
                  sourceUrl: 'https://example.com/test-only',
                  precision: 'test fixture',
                ),
                shadeCalculator: (r, at) async {
                  await shadeGate?.future;
                  return {
                    'shade': r.distanceMeters == 500 ? .2 : .8,
                    'coverage': 1.0,
                    'distance': r.distanceMeters,
                    'night': 0.0,
                  };
                },
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await reveal(t, toggle);
    await t.tap(toggle);
    await t.pumpAndSettle();
    gps.stream.add(
      WalkingLocationFix(origin, DateTime.now(), accuracy: 5, speed: 1),
    );
    await t.pump();
    await t.pump();
  }

  List<CityWalkingRoute> get replacement => [
    CityWalkingRoute(
      WalkingGeometry(
        points: [origin, end],
        durationSeconds: 300,
        sourceUrl: 'https://example.com/test-only',
        accessReviewed: false,
      ),
      500,
    ),
  ];
  Future<void> refresh(WidgetTester t) async {
    service.pending = Completer<List<CityWalkingRoute>>();
    final calculate = find.byKey(const ValueKey('route-refresh-button'));
    await reveal(t, calculate, step: 300);
    await t.tap(calculate);
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    location.dispose();
    settings.dispose();
    service.client.close();
    await gps.stream.close();
  }
}

void main() {
  testWidgets(
    'a temporary native GPS failure keeps navigation and reconnects',
    (t) async {
      final j = Journey();
      await j.mount(t);
      j.gps.stream.addError(StateError('temporary GPS loss'));
      await t.pump();
      expect(j.location.tracking, true);
      expect(j.location.error, isNull);
      expect(j.location.trackingError, isNotNull);
      await t.pump(const Duration(seconds: 5));
      expect(j.gps.stream.hasListener, true);
      j.gps.stream.add(WalkingLocationFix(origin, DateTime.now(), accuracy: 5));
      await t.pumpAndSettle();
      expect(j.location.tracking, true);
      expect(j.location.trackingError, isNull);
      expect(
        t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
        hasLength(1),
      );
      expect(t.takeException(), isNull);
      await j.close(t);
    },
  );

  testWidgets('repeated movement retains the current path after one retry', (
    t,
  ) async {
    final j = Journey();
    await j.mount(t);
    final before = j.service.walks;
    await j.refresh(t);
    final first = j.service.pending!;
    final second = Completer<List<CityWalkingRoute>>();
    j.service.pending = second;
    j.gps.stream.add(
      WalkingLocationFix(
        const Coordinates(latitude: 36.191, longitude: -115.282),
        DateTime.now(),
        accuracy: 5,
        speed: 1,
      ),
    );
    await t.pump();
    first.complete(j.replacement);
    await t.pump();
    await t.pump();
    expect(j.service.walks, before + 2);
    j.gps.stream.add(
      WalkingLocationFix(
        const Coordinates(latitude: 36.192, longitude: -115.283),
        DateTime.now(),
        accuracy: 5,
        speed: 1,
      ),
    );
    await t.pump();
    second.complete(j.replacement);
    await t.pumpAndSettle();
    expect(j.service.walks, before + 2);
    expect(
      t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
      hasLength(1),
    );
    final error = find.textContaining('Location moved during the update');
    await j.reveal(t, error, step: -100);
    expect(error, findsWidgets);
    expect(j.location.tracking, true);
    await j.close(t);
  });

  testWidgets(
    'a stale fix cannot be revived by completion of an asynchronous update',
    (t) async {
      var at = DateTime.now();
      final j = Journey(now: () => at);
      await j.mount(t);
      await j.refresh(t);
      at = at.add(const Duration(seconds: 20));
      j.service.pending!.complete(j.replacement);
      await t.pumpAndSettle();
      expect(
        t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
        hasLength(1),
      );
      expect(find.textContaining('Waiting for GPS'), findsWidgets);
      expect(j.location.tracking, true);
      await j.close(t);
    },
  );
  testWidgets('slow updates re-anchor once to the current walking position', (
    t,
  ) async {
    final j = Journey();
    await j.mount(t);
    final before = j.service.walks;
    await j.refresh(t);
    const moved = Coordinates(latitude: 36.191, longitude: -115.282);
    j.gps.stream.add(
      WalkingLocationFix(moved, DateTime.now(), accuracy: 5, speed: 1),
    );
    await t.pump();
    final pending = j.service.pending!;
    j.service.pending = null;
    pending.complete(j.replacement);
    await t.pumpAndSettle();
    expect(j.service.usedStart, moved);
    expect(j.service.walks, before + 2);
    expect(j.location.tracking, true);
    expect(t.takeException(), isNull);
    await j.close(t);
  });
  testWidgets(
    'a newer preference wins over manual corridor work already in flight',
    (t) async {
      final j = Journey();
      await j.mount(t);
      await j.reveal(t, j.toggle);
      await t.tap(j.toggle);
      await t.pumpAndSettle();
      final alternative = find.byKey(
        const ValueKey('route-preference-mostShade'),
      );
      await j.reveal(t, alternative, step: -100);
      await t.tap(alternative);
      await t.pumpAndSettle();
      await j.reveal(t, j.toggle);
      await t.tap(j.toggle);
      await t.pumpAndSettle();
      j.gps.stream.add(
        WalkingLocationFix(origin, DateTime.now(), accuracy: 5, speed: 1),
      );
      await t.pump();
      await j.refresh(t);
      final fast = find.byKey(
        const ValueKey('route-preference-fastest'),
        skipOffstage: false,
      );
      await t.ensureVisible(fast);
      await t.pump();
      await t.tap(fast);
      await t.pump();
      final pending = j.service.pending!;
      j.service.pending = null;
      pending.complete(await j.service.walkAlternatives(origin, end));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: fast, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      expect(j.location.tracking, true);
      await j.close(t);
    },
  );
  testWidgets('starting a walk preserves an explicitly selected alternative', (
    t,
  ) async {
    final j = Journey();
    await j.mount(t);

    await j.reveal(t, j.toggle);
    await t.tap(j.toggle);
    await t.pumpAndSettle();
    final alternative = find.byKey(
      const ValueKey('route-preference-mostShade'),
    );
    await j.reveal(t, alternative, step: -100);
    await t.tap(alternative);
    await t.pumpAndSettle();
    await j.reveal(t, j.toggle);
    await t.tap(j.toggle);
    await t.pumpAndSettle();
    await j.reveal(t, alternative, step: -100);
    expect(
      find.descendant(
        of: alternative,
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(j.location.tracking, true);
    await j.close(t);
  });
  testWidgets('arrival cancels a pending reroute and preserves arrival', (
    t,
  ) async {
    final j = Journey();
    await j.mount(t);
    await j.refresh(t);
    j.gps.stream.add(
      WalkingLocationFix(end, DateTime.now().toUtc(), accuracy: 5, speed: 1),
    );
    await t.pump();
    await t.pump();
    expect(j.location.tracking, false);
    j.service.pending!.complete(j.replacement);
    await t.pumpAndSettle();
    expect(
      t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
      hasLength(1),
    );
    expect(find.text('Stop navigation'), findsNothing);
    await j.close(t);
  });
  testWidgets('failed refresh retains the followed geometry and GPS', (
    t,
  ) async {
    final j = Journey();
    await j.mount(t);
    await j.refresh(t);
    j.service.pending!.completeError(
      const FormatException('Controlled provider outage'),
    );
    await t.pumpAndSettle();
    expect(j.location.tracking, true);
    expect(
      t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
      hasLength(1),
    );
    expect(t.takeException(), isNull);
    await j.close(t);
  });
  testWidgets(
    'active reroute swaps geometry and shade atomically after all comparisons',
    (t) async {
      final j = Journey();
      await j.mount(t);
      await j.refresh(t);
      j.shadeGate = Completer<void>();
      j.service.pending!.complete(j.replacement);
      await t.pump();
      await t.pump();
      expect(
        t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
        hasLength(1),
      );
      expect(j.location.tracking, true);
      j.shadeGate!.complete();
      await t.pumpAndSettle();
      expect(
        t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
        hasLength(1),
      );
      await j.close(t);
    },
  );
  testWidgets(
    'stop stays available during network or shade work and invalidates late results',
    (t) async {
      final j = Journey();
      await j.mount(t);
      await j.refresh(t);
      await j.reveal(t, j.toggle);
      expect(t.widget<FilledButton>(j.toggle).onPressed, isNotNull);
      await t.tap(j.toggle);
      await t.pumpAndSettle();
      expect(j.location.tracking, false);
      expect(j.gps.stream.hasListener, false);
      j.service.pending!.complete(j.replacement);
      await t.pumpAndSettle();
      expect(
        t.widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>)).polylines,
        hasLength(1),
      );
      expect(find.text('Stop navigation'), findsNothing);
      await j.close(t);
    },
  );
}
