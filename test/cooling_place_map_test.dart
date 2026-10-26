import 'cooling_asset_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/cooling_place_map_page.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';

import 'shared_location_test.dart' show TestPosition;

void main() {
  for (final official in [true, false]) {
    for (final gpsEnabled in [true, false]) {
      testWidgets(
        'card map, details and destination: official=$official GPS=$gpsEnabled',
        (tester) async {
          final settings = AppSettings(
            read: () async => null,
            write: (_) async {},
          );
          final gps = TestPosition();
          final location = AppLocation(settings, service: gps);
          await location.choose(
            gpsEnabled ? LocationChoice.session : LocationChoice.never,
          );
          final directory = OfficialCoolingDirectory.parse(
            jsonDecode(
              File('data/cooling_centers/official_directory.json')
                  .readAsStringSync(),
            ),
          );
          final community = UnofficialCoolingDirectory.parse(
            jsonDecode(
              File('data/cooling_centers/unofficial_directory.json')
                  .readAsStringSync(),
            ),
          );
          CoolingDestination? selected;
          var selections = 0;
          await tester.pumpWidget(
            LocationScope(
              location: location,
              child: MaterialApp(
                home: Scaffold(
                  body: OfficialCoolingPage(
                    discoveryAssetsLoader: loadTestDiscoveryAssets,
                    loader: () async => directory,
                    unofficialLoader: () async => community,
                    mapTilesEnabled: false,
                    onDestinationSelected: (d) {
                      selected = d;
                      selections++;
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!gpsEnabled) {
            await tester.enterText(find.byType(TextField), '89128');
            await tester.pumpAndSettle();
          }
          {
            await tester.tap(find.text(official ? 'Libraries' : 'Parks'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Station report'), findsNothing);
          expect(find.text('Place details'), findsNothing);
          final card = find
              .byWidgetPredicate(
                (w) =>
                    w is InkWell &&
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'cooling-map-',
                    ),
              )
              .first;
          final title = find
              .descendant(of: card, matching: find.byType(Text))
              .first;
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          await tester.tap(title);
          await tester.pumpAndSettle();
          final page = tester.widget<CoolingPlaceMapPage>(
            find.byType(CoolingPlaceMapPage),
          );
          final point = page.place['coordinates'] as Map;
          final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
          expect(
            map.mapController!.camera.center.latitude,
            closeTo(point['latitude'] as double, 1e-7),
          );
          expect(
            map.mapController!.camera.center.longitude,
            closeTo(point['longitude'] as double, 1e-7),
          );
          expect(find.text(page.place['address'] as String), findsOneWidget);
          expect(
            find.text(
              gpsEnabled ? 'Route from my location' : 'Set destination',
            ),
            findsOneWidget,
          );
          final calls = gps.calls;
          await tester.tap(find.byTooltip('Place details'));
          await tester.pumpAndSettle();
          expect(find.text('Select as planned destination'), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          final button = find.byKey(const ValueKey('cooling-map-destination'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(selected?.id, page.place['id']);
          expect(selected?.startFromCurrentLocation, isTrue);
          expect(selections, 1);
          expect(find.byType(CoolingPlaceMapPage), findsNothing);
          expect(find.byType(OfficialCoolingPage), findsOneWidget);
          expect(gps.calls, calls);
          expect(tester.takeException(), null);
          await tester.pumpWidget(const SizedBox());
          location.dispose();
          settings.dispose();
        },
      );
    }
  }

  testWidgets(
    'unsupported community destination stays disabled at large text',
    (tester) async {
      final directory = UnofficialCoolingDirectory.parse(
        jsonDecode(
          File('data/cooling_centers/unofficial_directory.json')
              .readAsStringSync(),
        ),
      );
      final place = directory.places.singleWhere(
        (p) => p['name'] == 'Duck Creek Park',
      );
      tester.view.physicalSize = const Size(320, 650);
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
          home: CoolingPlaceMapPage(
            place: place,
            official: false,
            tilesEnabled: false,
            origin: const Coordinates(latitude: 36.19, longitude: -115.28),
            onDetails: (_) {},
            onDestinationSelected: (_) =>
                fail('Unsupported point must not be selected'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('cooling-map-destination'));
      await tester.ensureVisible(button);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.text('Outside route planning area'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
