import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';
import 'package:heatwatch/core/saved_places/saved_places_widgets.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';
import 'package:heatwatch/features/cool_spots/presentation/cooling_place_map_page.dart';

import 'cooling_asset_support.dart';

void main() {
  testWidgets(
    'heart a cooling card without opening its map or changing its source',
    (t) async {
      final saved = SavedPlaces(read: () async => null, write: (_) async {});
      await saved.load();
      final official = OfficialCoolingDirectory.parse(
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
      await t.pumpWidget(
        SavedPlacesScope(
          places: saved,
          child: MaterialApp(
            home: Scaffold(
              body: OfficialCoolingPage(
                discoveryAssetsLoader: loadTestDiscoveryAssets,
                loader: () async => official,
                unofficialLoader: () async => community,
                mapTilesEnabled: false,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '89119');
      await t.pumpAndSettle();
      final card = find.byKey(
        const ValueKey('cooling-map-community-south-premium-outlets'),
      );
      await t.scrollUntilVisible(
        card,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      final heart = find.descendant(
        of: card,
        matching: find.byType(FavoriteButton),
      );
      await t.ensureVisible(heart);
      await t.tap(heart);
      await t.pumpAndSettle();
      final source = community.places.firstWhere(
        (p) => p['id'] == 'community-south-premium-outlets',
      );
      expect(saved.favorites.single.name, source['name']);
      expect(
        saved.favorites.single.sourceUrl,
        source['coordinates']['sourceUrl'],
      );
      expect(
        saved.favorites.single.precision,
        source['coordinates']['precision'],
      );
      expect(find.byType(CoolingPlaceMapPage), findsNothing);
      await t.tap(heart);
      await t.pumpAndSettle();
      expect(saved.favorites, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      saved.dispose();
    },
  );
}
