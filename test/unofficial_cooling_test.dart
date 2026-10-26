import 'cooling_asset_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';
import 'package:heatwatch/features/cool_spots/presentation/unofficial_place_report.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_actions.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/models/coordinates.dart';

Map<String, dynamic> data() => jsonDecode(
  File('data/cooling_centers/unofficial_directory.json').readAsStringSync(),
) as Map<String, dynamic>;
OfficialCoolingDirectory official() => OfficialCoolingDirectory.parse(
  jsonDecode(
    File('data/cooling_centers/official_directory.json').readAsStringSync(),
  ),
);
void main() {
  testWidgets(
    'community distances use the shared position and show the nearest park first',
    (tester) async {
      final directory = UnofficialCoolingDirectory.parse(data());
      final settings = AppSettings(read: () async => null, write: (_) async {});
      final location = AppLocation(settings);
      final park = directory.places.singleWhere(
        (p) => p['name'] == 'Angel Park',
      );
      location.position = Coordinates(
        latitude: park['coordinates']['latitude'],
        longitude: park['coordinates']['longitude'],
      );
      await tester.pumpWidget(
        LocationScope(
          location: location,
          child: MaterialApp(
            home: Scaffold(
              body: OfficialCoolingPage(
                discoveryAssetsLoader: loadTestDiscoveryAssets,
                loader: () async => official(),
                unofficialLoader: () async => directory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parks'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nearest first · straight-line distance'),
        findsOneWidget,
      );
      final firstCard = find.byType(Card).first;
      expect(
        find.descendant(of: firstCard, matching: find.text('Angel Park')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstCard, matching: find.text('0.0 mi · Parks')),
        findsOneWidget,
      );
      expect(find.text('Sort near me'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      location.dispose();
      settings.dispose();
    },
  );
  testWidgets(
    'southern water stops remain listed but cannot send an unsupported routing point',
    (tester) async {
      final directory = UnofficialCoolingDirectory.parse(data());
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: UnofficialPlaceReport(
            place: directory.places.singleWhere(
              (p) => p['name'] == 'Duck Creek Park',
            ),
            directory: directory,
            actions: const CoolingActions(),
            onDestinationSelected: (_) => called = true,
          ),
        ),
      );
      expect(find.text('Drinking water · outdoors'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(called, isFalse);
      expect(find.text('Outside route planning area'), findsOneWidget);
    },
  );
  test('70 distinct sourced places; original human-fountain evidence survives import', () {
    final directory = UnofficialCoolingDirectory.parse(data());
    expect(directory.places, hasLength(70));
    expect(directory.places.map((p) => p['name']).toSet(), hasLength(70));
    expect(
      directory.places.where(
        (p) => (p['methods'] as List).contains('drinkingWater'),
      ),
      hasLength(49),
    );
    expect(
      directory.places.where(
        (p) => (p['methods'] as List).contains('airConditioning'),
      ),
      hasLength(19),
    );
    final raw = jsonDecode(
      File('data/cooling_centers/unofficial_sources/human-fountains.json')
          .readAsStringSync(),
    );
    final original = {
      for (final f in raw['features']) f['attributes']['OBJECTID']: f,
    };
    var mapped = 0;
    for (final place in directory.places) {
      expect(place['officialCoolingStation'], isFalse);
      final evidence = place['evidence'] as Map;
      if (!(place['id'] as String).startsWith('community-added-')) {
        expect(place['hours'], isNull);
      }
      if (evidence['fountains'] != null) {
        for (final fountain in evidence['fountains']) {
          mapped++;
          final feature = original[fountain['featureId']];
          expect(feature['attributes']['TYPE'], 'Fountain Drinking');
          expect(fountain['latitude'], feature['geometry']['y']);
          expect(fountain['longitude'], feature['geometry']['x']);
        }
      }
      if (evidence['trailId'] != null) {
        final html = File(
          'data/cooling_centers/unofficial_sources/snhd-${evidence['trailId']}.html',
        ).readAsStringSync();
        expect(html, contains('title="Drinking Fountains"'));
        expect(
          (place['coordinates'] as Map)['latitude'],
          double.parse(
            RegExp('class="latitude">([^<]+)').firstMatch(html)!.group(1)!,
          ),
        );
      }
    }
    expect(mapped, 94);
    final mall = directory.places.singleWhere((p) => p['kind'] == 'mall');
    expect((mall['evidence'] as Map)['osmId'], 38358961);
    expect(mall['methods'], ['airConditioning']);
  });
  test('malformed coordinates, unsupported cooling and broken sources are rejected', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (d) => d['places'][0]['coordinates']['latitude'] = double.nan,
      (d) => d['places'][0]['methods'] = [],
      (d) => d['places'][0]['methods'] = ['decorativeFountain'],
      (d) => d['places'][0]['sourceIds'] = ['missing'],
      (d) => d['places'][0]['officialCoolingStation'] = true,
      (d) => d['places'][1]['id'] = d['places'][0]['id'],
    ]) {
      final d = data();
      mutate(d);
      expect(() => UnofficialCoolingDirectory.parse(d), throwsFormatException);
    }
  });
  testWidgets('indoor category and route handoff use sourced coordinates', (
    tester,
  ) async {
    final directory = UnofficialCoolingDirectory.parse(data());
    CoolingDestination? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfficialCoolingPage(
            discoveryAssetsLoader: loadTestDiscoveryAssets,
            loader: () async => official(),
            unofficialLoader: () async => directory,
            onDestinationSelected: (d) => destination = d,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '89119');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indoor Places'));
    await tester.pumpAndSettle();
    expect(find.text('8 places within 5 miles of 89119'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Las Vegas South Premium Outlets'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Las Vegas South Premium Outlets'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('cooling-map-community-south-premium-outlets')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey('cooling-map-community-south-premium-outlets'),
        ),
        matching: find.byTooltip('Place details'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('cost extra'), findsNothing);
    await tester.tap(find.text('Plan a route here'));
    await tester.pumpAndSettle();
    expect(destination!.id, 'community-south-premium-outlets');
    expect(destination!.location.latitude, 36.0539382);
    expect(
      destination!.sourceUrl,
      'https://www.openstreetmap.org/way/38358961',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a failed official update does not block the bundled unofficial directory',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficialCoolingPage(
              discoveryAssetsLoader: loadTestDiscoveryAssets,
              loader: () async => throw const FormatException('fixture'),
              unofficialLoader: () async =>
                  UnofficialCoolingDirectory.parse(data()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '89119');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Indoor Places'));
      await tester.pumpAndSettle();
      expect(find.text('8 places within 5 miles of 89119'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
