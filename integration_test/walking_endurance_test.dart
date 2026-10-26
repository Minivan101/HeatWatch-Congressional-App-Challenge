import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/shade_route/presentation/city_trip_panel.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

import '../test/weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

class PublicGPS extends LocationService {
  PublicGPS(this.point);
  final Coordinates point;
  final updates = StreamController<WalkingLocationFix>.broadcast(sync: true);
  @override
  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async => point;
  @override
  Stream<WalkingLocationFix> watchPosition() => updates.stream;
}

class ObservedWalking extends PedestrianTripService {
  final attempts = <DateTime>[];
  var successful = 0;
  @override
  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async {
    attempts.add(DateTime.now());
    debugPrint('SOAK route attempt ${attempts.length}');
    final result = await super.walkAlternatives(start, end, via: via);
    successful++;
    return result;
  }
}

Coordinates advance(
  CityWalkingRoute route,
  Coordinates current,
  double meters,
) {
  final target = walkingProgress(route, current).alongMeters + meters;
  double cumulative = 0;
  final p = route.geometry.points;
  for (var i = 0; i < p.length - 1; i++) {
    final length = walkingDistance(p[i], p[i + 1]);
    if (length > 0 && cumulative + length >= target) {
      final f = ((target - cumulative) / length).clamp(0.0, 1.0);
      return Coordinates(
        latitude: p[i].latitude + (p[i + 1].latitude - p[i].latitude) * f,
        longitude: p[i].longitude + (p[i + 1].longitude - p[i].longitude) * f,
      );
    }
    cumulative += length;
  }
  return p.last;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '21-minute foreground walking, timed shade refresh, GPS outage and three choices',
    (t) async {
      const enabled = bool.fromEnvironment('HEATWATCH_NAVIGATION_SOAK');
      if (!enabled) return;
      const start = Coordinates(latitude: 36.191439, longitude: -115.302102);
      const end = Coordinates(latitude: 36.1672, longitude: -115.1485);
      final service = ObservedWalking();
      final initial = await service.walkAlternatives(start, end);
      final gps = PublicGPS(initial.first.geometry.points.first);
      final settings = AppSettings(read: () async => null, write: (_) async {});
      await settings.load();
      await settings.update(preferencePromptSeen: true);
      final location = AppLocation(settings, service: gps);
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
                  destination: const CoolingDestination(
                    id: 'public-soak',
                    name: 'Downtown public map point',
                    address: 'Las Vegas',
                    location: end,
                    sourceUrl: 'https://routing.openstreetmap.de/about.html',
                    precision: 'public-coordinate endurance test',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var n = 0; n < 240; n++) {
        await t.pump(const Duration(milliseconds: 250));
        if (find
                .byKey(const ValueKey('walking-navigation-toggle'))
                .evaluate()
                .isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      final scroll = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      final toggle = find.byKey(const ValueKey('walking-navigation-toggle'));
      await t.scrollUntilVisible(toggle, 100, scrollable: scroll);
      await t.pumpAndSettle();
      await t.tap(toggle);
      await t.pumpAndSettle();
      var point = gps.point;
      gps.updates.add(
        WalkingLocationFix(
          point,
          DateTime.now(),
          accuracy: 5,
          heading: 90,
          speed: 1.5,
        ),
      );
      await t.pump();
      await t.pump();
      final started = DateTime.now();
      var samples = 0;
      for (var tick = 1; tick <= 42; tick++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 30)),
        );
        await t.pump();

        if (tick == 17 || tick == 18) {
          expect(find.textContaining('Waiting for GPS'), findsWidgets);
          debugPrint(
            'SOAK GPS outage observed at ${DateTime.now().difference(started).inSeconds}s',
          );
          continue;
        }
        final line = t
            .widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>))
            .polylines
            .last;
        final r = CityWalkingRoute(
          WalkingGeometry(
            points: line.points
                .map(
                  (p) =>
                      Coordinates(latitude: p.latitude, longitude: p.longitude),
                )
                .toList(),
            durationSeconds: 1000,
            sourceUrl: 'https://www.openstreetmap.org',
            accessReviewed: false,
          ),
          1000,
        );
        point = advance(r, point, 45);
        gps.updates.add(
          WalkingLocationFix(
            point,
            DateTime.now(),
            accuracy: 5,
            heading: 90,
            speed: 1.5,
          ),
        );
        samples++;
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
        expect(location.tracking, true);
        expect(find.textContaining('km remaining'), findsWidgets);
        expect(find.textContaining('%'), findsNothing);
        final camera = t
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera;
        expect(camera.center.latitude, closeTo(point.latitude, 1e-6));
        if ((tick == 4 || tick == 12 || tick == 30) &&
            find
                .byKey(const ValueKey('best-route-choice'))
                .evaluate()
                .isEmpty) {
          final label = tick == 4
              ? 'Most shade'
              : tick == 12
              ? 'Fastest route'
              : 'Most shade';
          await t.scrollUntilVisible(
            find.text(label),
            -100,
            scrollable: scroll,
          );
          await t.pump(const Duration(milliseconds: 300));
          await t.tap(find.text(label));
          for (var n = 0; n < 160; n++) {
            await t.pump(const Duration(milliseconds: 250));
            if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
              break;
            }
          }
          expect(location.tracking, true);
          debugPrint('SOAK preference $label selected');
        }
        if (tick % 2 == 0) {
          debugPrint(
            'SOAK ${DateTime.now().difference(started).inSeconds}s: $samples fixes, ${service.attempts.length} route attempts, ${service.successful} successful',
          );
        }
      }
      expect(
        DateTime.now().difference(started),
        greaterThanOrEqualTo(const Duration(minutes: 21)),
      );
      expect(service.attempts.length, greaterThanOrEqualTo(6));
      expect(service.successful, greaterThanOrEqualTo(4));
      await location.choose(LocationChoice.never);
      await t.pumpAndSettle();
      expect(gps.updates.hasListener, false);
      expect(location.tracking, false);
      debugPrint(
        'SOAK_DONE elapsedSeconds=${DateTime.now().difference(started).inSeconds} fixes=$samples attempts=${service.attempts.length} success=${service.successful}',
      );
      await t.pumpWidget(const SizedBox.shrink());
      location.dispose();
      settings.dispose();
      service.client.close();
      await gps.updates.close();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
