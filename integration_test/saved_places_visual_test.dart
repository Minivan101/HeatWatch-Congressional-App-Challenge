import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:heatwatch/app.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/demo/home_demo_data.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';

import '../test/saved_places_ui_test.dart' show settleSavedUI;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native saved-places preview with explicitly simulated weather', (
    t,
  ) async {
    final saved = SavedPlaces(read: () async => null, write: (_) async {});
    await saved.load();
    const place = SavedPlace(
      name: 'Las Vegas Library',
      address: 'Public place preview',
      point: Coordinates(latitude: 36.17, longitude: -115.14),
      sourceUrl: 'https://www.openstreetmap.org',
      precision: 'Preview fixture',
    );
    await saved.setLabel(PlaceLabel.home, place);
    await saved.toggleFavorite(place);
    final settings = AppSettings(
      read: () async => '{"location":"never","theme":"light"}',
      write: (_) async {},
    );
    final service = CityTripService(loadPlaces: () async => []);
    final now = DateTime.utc(2026, 7, 10, 20);
    final capture = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: HeatWatchApp(
          savedPlaces: saved,
          settings: settings,
          promptLocation: false,
          mapTilesEnabled: false,
          walkingService: service,
          demoControls: const Material(
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Text(
                'UI PREVIEW · simulated weather and saved places',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          weatherRepository: WeatherRepository(
            clock: () => now,
            cache: WeatherCache(),
            weather: HomeDemoWeather(now),
            alerts: HomeDemoAlerts(now),
          ),
        ),
      ),
    );
    await settleSavedUI(t);
    Future<void> screenshot(String name) async {
      await t.pumpAndSettle();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${(await getTemporaryDirectory()).path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await screenshot('heatwatch-saved-home');
    await t.ensureVisible(find.text('View all'));
    await t.tap(find.text('View all'));
    await screenshot('heatwatch-saved-manager');
    if (const bool.fromEnvironment('HEATWATCH_REVIEW_UI')) {
      debugPrint('HeatWatch UI screenshots ready');
      await Future<void>.delayed(const Duration(seconds: 30));
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    saved.dispose();
    settings.dispose();
    service.client.close();
  });
}
