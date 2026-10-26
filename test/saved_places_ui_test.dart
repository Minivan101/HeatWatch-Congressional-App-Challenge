import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/app.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/saved_places/place_search_sheet.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';
import 'package:heatwatch/core/saved_places/saved_places_widgets.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/heat_guard/demo/home_demo_data.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';

const publicPlace = CityPlace(
  'Public Library',
  '100 Test Street',
  Coordinates(latitude: 36.17, longitude: -115.14),
  sourceUrl: 'https://www.openstreetmap.org/node/100',
  precision: 'mapped point',
);

Future<void> settleSavedUI(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() async {
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    if (find
            .byType(LinearProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isEmpty) {
      break;
    }
  }
  await t.pump(const Duration(milliseconds: 400));
}

void main({bool native = false}) {
  testWidgets(
    'heart a search result, choose it, and find it again by its saved label',
    (t) async {
      final saved = SavedPlaces(read: () async => null, write: (_) async {});
      await saved.load();
      final service = CityTripService(loadPlaces: () async => [publicPlace]);
      CityPlace? selected;
      await t.pumpWidget(
        SavedPlacesScope(
          places: saved,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open place search'),
                  onPressed: () async {
                    selected = await showModalBottomSheet<CityPlace>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (sheet) => PlaceSearchSheet(
                        service: service,
                        start: false,
                        initial: '',
                        locationAvailable: false,
                        onSelect: (place) => Navigator.pop(sheet, place),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open place search'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Library');
      await t.tap(find.byTooltip('Search places'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Add to favorites: Public Library'));
      await t.pumpAndSettle();
      expect(saved.favorites.single.name, publicPlace.name);
      expect(
        selected,
        isNull,
        reason: 'Hearting a result must not dismiss the picker.',
      );
      await t.tap(find.text('Public Library').last);
      await t.pumpAndSettle();
      expect(selected?.point.latitude, publicPlace.point.latitude);
      await saved.rename(saved.favorites.single, 'Study spot');
      await t.tap(find.text('Open place search'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Study spot');
      await t.pumpAndSettle();
      expect(find.text('Study spot'), findsWidgets);
      await t.tap(find.widgetWithText(ListTile, 'Study spot'));
      await t.pumpAndSettle();
      expect(selected?.name, 'Study spot');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      service.client.close();
      saved.dispose();
    },
  );

  testWidgets(
    'Home shortcut opens a route; logo returns home from either tab and retains endpoints',
    (t) async {
      if (!native) {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
      }
      final saved = SavedPlaces(read: () async => null, write: (_) async {});
      await saved.load();
      await saved.setLabel(PlaceLabel.home, SavedPlace.fromCity(publicPlace));
      final settings = AppSettings(
        read: () async =>
            '{"location":"never","routePreferencePromptSeen":true}',
        write: (_) async {},
      );
      final now = DateTime.utc(2026, 7, 10, 20);
      final service = CityTripService(loadPlaces: () async => [publicPlace]);
      await t.pumpWidget(
        HeatWatchApp(
          savedPlaces: saved,
          settings: settings,
          weatherRepository: WeatherRepository(
            clock: () => now,
            cache: WeatherCache(),
            weather: HomeDemoWeather(now),
            alerts: HomeDemoAlerts(now),
          ),
          walkingService: service,
          promptLocation: false,
          mapTilesEnabled: false,
        ),
      );
      await settleSavedUI(t);
      final home = find.widgetWithText(ActionChip, 'Home');
      await t.ensureVisible(home);
      await t.pumpAndSettle();
      await t.tap(home);
      await t.pump();
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      final transition = t.widget<SlideTransition>(
        find
            .ancestor(
              of: find.byType(IndexedStack),
              matching: find.byType(SlideTransition),
            )
            .first,
      );
      if (!native) expect(transition.position.value.dx, greaterThan(0));
      await t.pump(const Duration(milliseconds: 120));
      expect(transition.position.value, Offset.zero);
      final endpoint = find.byKey(const ValueKey('route-destination-field'));
      expect(
        find.descendant(of: endpoint, matching: find.text('Public Library')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('home-logo')));
      if (!native) {
        await t.pump();
        final back = t.widget<SlideTransition>(
          find
              .ancestor(
                of: find.byType(IndexedStack),
                matching: find.byType(SlideTransition),
              )
              .first,
        );
        expect(back.position.value.dx, lessThan(0));
      }
      await t.pumpAndSettle();
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await t.tap(find.widgetWithText(NavigationDestination, 'CoolSpots'));
      await settleSavedUI(t);
      await t.tap(find.byKey(const ValueKey('home-logo')));
      await t.pumpAndSettle();
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await t.tap(find.widgetWithText(NavigationDestination, 'ShadeMap'));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: endpoint, matching: find.text('Public Library')),
        findsOneWidget,
      );
      if (!native) {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await t.pump();
        await t.tap(find.widgetWithText(NavigationDestination, 'Home'));
        await t.pump();
        final slide = t.widget<SlideTransition>(
          find
              .ancestor(
                of: find.byType(IndexedStack),
                matching: find.byType(SlideTransition),
              )
              .first,
        );
        expect(slide.position.value, Offset.zero);
        expect(
          t.widget<NavigationBar>(find.byType(NavigationBar)).animationDuration,
          Duration.zero,
        );
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      settings.dispose();
      saved.dispose();
      service.client.close();
    },
  );

  testWidgets(
    'set Home from search and use it immediately without enabling GPS',
    (t) async {
      final saved = SavedPlaces(read: () async => null, write: (_) async {});
      await saved.load();
      final service = CityTripService(loadPlaces: () async => [publicPlace]);
      String? selected;
      await t.pumpWidget(
        SavedPlacesScope(
          places: saved,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SavedPlacesSection(
                  service: service,
                  onSelect: (place) => selected = place.name,
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.widgetWithText(ActionChip, 'Home'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Library');
      await t.tap(find.byTooltip('Search places'));
      await t.pumpAndSettle();
      await t.tap(find.text('Public Library'));
      await t.pumpAndSettle();
      expect(saved.labeled(PlaceLabel.home)?.name, 'Public Library');
      await t.tap(find.widgetWithText(ActionChip, 'Home'));
      expect(selected, 'Public Library');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      service.client.close();
      saved.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'saved manager can edit Home, Work and labels at narrow width, large text, dark=$dark',
      (t) async {
        if (!native) {
          t.view.physicalSize = const Size(320, 700);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
        }
        final saved = SavedPlaces(read: () async => null, write: (_) async {});
        await saved.load();
        await saved.toggleFavorite(SavedPlace.fromCity(publicPlace));
        final service = CityTripService(loadPlaces: () async => [publicPlace]);
        await t.pumpWidget(
          SavedPlacesScope(
            places: saved,
            child: MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.8)),
                child: child!,
              ),
              home: Scaffold(
                body: SavedPlacesSheet(service: service, onSelect: (_) {}),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> openMenu(String label) async {
          final target = find.byWidgetPredicate(
            (w) => w is PopupMenuButton<String> && w.tooltip == 'Edit $label',
          );
          for (
            var i = 0;
            i < 12 && target.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await t.drag(find.byType(ListView), const Offset(0, -100));
            await t.pumpAndSettle();
          }
          expect(target.hitTestable(), findsOneWidget);
          await t.tap(target.hitTestable());
          await t.pumpAndSettle();
        }

        await openMenu('Public Library');
        await t.tap(find.text('Set as Work'));
        await t.pumpAndSettle();
        expect(saved.labeled(PlaceLabel.work)?.name, publicPlace.name);
        await openMenu('Public Library');
        await t.tap(find.text('Edit label'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'Study spot');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved.favorites.single.title, 'Study spot');
        await openMenu('Study spot');
        await t.tap(find.text('Remove favorite'));
        await t.pumpAndSettle();
        expect(saved.favorites, isEmpty);
        expect(saved.labeled(PlaceLabel.work)?.title, 'Study spot');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        saved.dispose();
        service.client.close();
      },
    );
  }
}
