import 'dart:async';

import '../test/support/recorded_vegas_walk.dart';

import 'package:heatwatch/features/shade_route/services/pedestrian_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:integration_test/integration_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/shade_route/presentation/city_trip_panel.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';

import '../test/city_trip_map_test.dart'
    show MapService, LiveMapPosition, origin, end;
import '../test/weather_repository_test.dart'
    show WeatherFake, AlertsFake, readingAt, alertReading;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native foreground navigation, camera rotation, reroute and opt-out',
    (tester) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      final gps = LiveMapPosition();
      final location = AppLocation(settings, service: gps);
      await location.choose(LocationChoice.session);
      final service = MapService();
      final now = DateTime.now().toUtc();
      final weather = WeatherRepository(
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: AlertsFake((p) async => alertReading(p, now, [])),
        cache: WeatherCache(),
      );
      await tester.pumpWidget(
        LocationScope(
          location: location,
          child: MaterialApp(
            home: Scaffold(
              body: CityTripPanel(
                service: service,
                weather: weather,
                tilesEnabled: false,
                destination: const CoolingDestination(
                  id: 'native-fixture',
                  name: 'Test-only Vegas endpoint',
                  address: 'Public-coordinate test fixture',
                  location: end,
                  sourceUrl: 'https://example.com/test-only',
                  precision: 'test',
                ),
                shadeCalculator: (route, _) async => {
                  'shade': .3,
                  'coverage': 1.0,
                  'distance': route.distanceMeters,
                  'night': 0.0,
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final drawer = find.byType(DraggableScrollableSheet);
      final scroll = drawer.evaluate().isEmpty
          ? find.byType(Scrollable).first
          : find
                .descendant(of: drawer, matching: find.byType(Scrollable))
                .first;
      final start = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(start, 100, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      final at = DateTime.now();
      const point = Coordinates(latitude: 36.1901, longitude: -115.2802);
      gps.stream.add(
        WalkingLocationFix(
          point,
          at.subtract(const Duration(seconds: 10)),
          accuracy: 5,
          heading: 90,
          speed: 1,
        ),
      );
      await tester.pump();
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(point.latitude, 1e-6),
      );
      expect(map.mapController!.camera.rotation, closeTo(-90, 1e-6));
      expect(find.textContaining('km remaining'), findsWidgets);
      expect(find.textContaining('%'), findsNothing);
      expect(gps.calls, 1);
      expect(service.walks, 1);

      final existing = tester
          .widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>))
          .polylines
          .length;
      service.pending = Completer();
      final calculate = find.text('Calculate walking route & shade');
      await tester.scrollUntilVisible(calculate, -100, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(calculate);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(location.tracking, true);
      expect(
        tester
            .widget<PolylineLayer<int>>(find.byType(PolylineLayer<int>))
            .polylines
            .length,
        existing,
      );
      final pending = service.pending!;
      service.pending = null;
      pending.complete(await service.walkAlternatives(origin, end));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final walksBeforeDeviation = service.walks;
      const off = Coordinates(latitude: 36.192, longitude: -115.28);
      gps.stream.add(
        WalkingLocationFix(
          off,
          at.subtract(const Duration(seconds: 7)),
          accuracy: 5,
        ),
      );
      await tester.pump();
      await tester.pump();
      gps.stream.add(
        WalkingLocationFix(
          off,
          at.subtract(const Duration(seconds: 1)),
          accuracy: 5,
        ),
      );
      await tester.pumpAndSettle();
      expect(service.walks, walksBeforeDeviation + 1);
      await location.choose(LocationChoice.never);
      await tester.pumpAndSettle();
      expect(gps.stream.hasListener, false);
      expect(find.byKey(const ValueKey('walking-route-0')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      location.dispose();
      settings.dispose();
      service.client.close();
      await gps.stream.close();
    },
  );
  testWidgets(
    'real long Vegas walk has shade, instructions and in-app GPS following',
    (tester) async {
      const startPoint = Coordinates(
        latitude: 36.191439,
        longitude: -115.302102,
      );
      const targetPoint = Coordinates(latitude: 36.1672, longitude: -115.1485);
      const recorded = bool.fromEnvironment('HEATWATCH_RECORDED_WALKING');
      final service = recorded
          ? RecordedWalkingService()
          : PedestrianTripService();

      debugPrint(
        recorded
            ? 'WALKING_CHECK_SOURCE recorded-public-response'
            : 'WALKING_CHECK_SOURCE live-free-provider',
      );
      final routes = await service.walkAlternatives(startPoint, targetPoint);
      expect(routes.first.distanceMeters, greaterThan(15000));
      expect(routes.first.steps, isNotEmpty);
      final settings = AppSettings(
        read: () => nullFuture(),
        write: (_) async {},
      );
      await settings.update(preferencePromptSeen: true);
      final nativeShade = <Map<String, dynamic>>[];
      final shade = RouteShadeRepository();
      final gps = LongWalkPosition(startPoint);
      final location = AppLocation(settings, service: gps);
      await location.choose(LocationChoice.session);
      final now = DateTime.now().toUtc();
      final weather = WeatherRepository(
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: AlertsFake((p) async => alertReading(p, now, [])),
        cache: WeatherCache(),
      );
      await tester.pumpWidget(
        LocationScope(
          location: location,
          child: MaterialApp(
            home: Scaffold(
              body: CityTripPanel(
                service: service,
                weather: weather,
                tilesEnabled: false,
                shadeCalculator: (route, at) async {
                  final result = await shade.calculate(route.geometry, at);
                  nativeShade.add(result);
                  return result;
                },
                destination: const CoolingDestination(
                  id: 'public-long-walk',
                  name: 'Downtown public map point',
                  address: 'Las Vegas',
                  location: targetPoint,
                  sourceUrl: 'https://routing.openstreetmap.de/about.html',
                  precision: 'public test coordinate',
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 240; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.textContaining('km walking').evaluate().isNotEmpty &&
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
      final summaries = find.textContaining('km walking');
      await tester.scrollUntilVisible(summaries.first, 100, scrollable: scroll);
      await tester.pumpAndSettle();
      expect(summaries, findsWidgets);
      expect(nativeShade, isNotEmpty);
      for (final result in nativeShade) {
        expect(result['distance'], greaterThan(15000));
        expect(result['heights'], greaterThan(500));
        expect(result['arrival'], isNotNull);
        if (recorded) expect(result['timingModel'], 'uniform-average-pace');
        final times = result['timeTotals'] as Map;
        final sum = times.values.fold<double>(
          0,
          (total, value) => total + (value as num).toDouble(),
        );
        expect(sum, closeTo((result['duration'] as num).toDouble(), .01));
        expect(times['unknown'], greaterThanOrEqualTo(0));
      }
      expect(find.textContaining('Shade comparison unavailable'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      final toggle = find.byKey(const ValueKey('walking-navigation-toggle'));
      await tester.scrollUntilVisible(toggle, 100, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(location.tracking, true);
      final point = routes.first.geometry.points[20];
      gps.stream.add(
        WalkingLocationFix(
          point,
          DateTime.now(),
          accuracy: 5,
          heading: 90,
          speed: 1,
        ),
      );
      await tester.pump();
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(point.latitude, 1e-6),
      );
      expect(map.mapController!.camera.rotation, closeTo(-90, 1e-6));
      expect(find.textContaining('km remaining'), findsWidgets);
      expect(tester.takeException(), isNull);
      await location.choose(LocationChoice.never);
      await tester.pumpAndSettle();
      expect(gps.stream.hasListener, false);
      await tester.pumpWidget(const SizedBox.shrink());
      location.dispose();
      settings.dispose();
      service.client.close();
      await gps.stream.close();
    },
  );
}

Future<String?> nullFuture() async => null;

class LongWalkPosition extends LocationService {
  LongWalkPosition(this.point);
  final Coordinates point;
  final stream = StreamController<WalkingLocationFix>.broadcast(sync: true);
  @override
  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async => point;
  @override
  Stream<WalkingLocationFix> watchPosition() => stream.stream;
}
