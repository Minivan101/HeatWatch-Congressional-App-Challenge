import 'cooling_asset_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';
import 'package:heatwatch/features/cool_spots/presentation/cooling_place_map_page.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_actions.dart';

class DirectionsRecorder extends CoolingActions {
  Map<String, dynamic>? place;
  @override
  Future<bool> directions(
    Map<String, dynamic> value, {
    Coordinates? origin,
  }) async {
    place = value;
    return true;
  }
}

void main() {
  final official = OfficialCoolingDirectory.parse(
    jsonDecode(
      File('data/cooling_centers/official_directory.json').readAsStringSync(),
    ),
  );
  final community = UnofficialCoolingDirectory.parse(
    jsonDecode(
      File('data/cooling_centers/unofficial_directory.json').readAsStringSync(),
    ),
  );

  test('directions encodes a public address and only a supplied origin', () {
    final place = community.places.first;
    final without = CoolingActions.directionsUri(place);
    expect(without.queryParameters.containsKey('origin'), isFalse);
    expect(
      without.queryParameters['destination'],
      '${place['name']}, ${place['address']}',
    );
    final withOrigin = CoolingActions.directionsUri(
      place,
      origin: const Coordinates(latitude: 36.1, longitude: -115.1),
    );
    expect(withOrigin.queryParameters['origin'], '36.1,-115.1');
    expect(withOrigin.queryParameters['travelmode'], 'walking');
  });

  testWidgets('metric nearby places can hand a destination to ShadeMap', (
    tester,
  ) async {
    final settings = AppSettings(read: () async => null, write: (_) async {});
    await settings.update(useImperial: false);
    final actions = DirectionsRecorder();
    CoolingDestination? selected;
    await tester.pumpWidget(
      SettingsScope(
        settings: settings,
        child: MaterialApp(
          home: Scaffold(
            body: OfficialCoolingPage(
              discoveryAssetsLoader: loadTestDiscoveryAssets,
              loader: () async => official,
              unofficialLoader: () async => community,
              actions: actions,
              onDestinationSelected: (destination) => selected = destination,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '89119');
    await tester.pumpAndSettle();
    expect(find.textContaining('within 8.0 km of 89119'), findsOneWidget);
    final card = find.byKey(
      const ValueKey('cooling-map-community-south-premium-outlets'),
    );
    await tester.scrollUntilVisible(
      card,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: card, matching: find.text('Directions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ShadeMap'));
    await tester.pumpAndSettle();
    expect(selected?.name, 'Las Vegas South Premium Outlets');
    expect(actions.place, isNull);
    settings.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'discovery categories, map pins and directions at large text dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 650);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final actions = DirectionsRecorder();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: OfficialCoolingPage(
                discoveryAssetsLoader: loadTestDiscoveryAssets,
                loader: () async => official,
                unofficialLoader: () async => community,
                mapTilesEnabled: false,
                actions: actions,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tapText(String text) async {
          await tester.scrollUntilVisible(
            find.text(text),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(text));
          await tester.pumpAndSettle();
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        await tester.enterText(find.byType(TextField), '89119');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Indoor Places'));
        await tapText('Indoor Places');
        await tester.scrollUntilVisible(
          find.text('8 places within 5 miles of 89119'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('8 places within 5 miles of 89119'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Las Vegas South Premium Outlets'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Las Vegas South Premium Outlets'), findsOneWidget);
        expect(find.textContaining('Hours'), findsNothing);
        expect(find.text('Open'), findsNothing);
        final outletCard = find.byKey(
          const ValueKey('cooling-map-community-south-premium-outlets'),
        );
        final directions = find.descendant(
          of: outletCard,
          matching: find.text('Directions'),
        );
        await tester.ensureVisible(directions);
        await tester.tap(directions);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Google Maps'));
        await tester.pumpAndSettle();
        expect(actions.place?['id'], 'community-south-premium-outlets');

        await tester.scrollUntilVisible(
          find.text('Map'),
          -180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Map'));
        await tester.pumpAndSettle();
        expect(find.byType(FlutterMap), findsOneWidget);
        final pin = find.byTooltip('Las Vegas South Premium Outlets');
        await tester.ensureVisible(pin);
        await tester.pumpAndSettle();
        await tester.tap(pin);
        await tester.pumpAndSettle();
        expect(find.byType(CoolingPlaceMapPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
