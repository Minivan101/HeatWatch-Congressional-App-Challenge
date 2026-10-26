import 'cooling_asset_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_actions.dart';
import 'package:heatwatch/features/shade_route/presentation/shade_route_page.dart';

class FakeActions extends CoolingActions {
  String? dialed;
  String? opened;
  @override
  Future<bool> dial(String number) async {
    dialed = number;
    return true;
  }

  @override
  Future<bool> openSource(String url) async {
    opened = url;
    return true;
  }
}

class FakeLocation extends LocationService {
  const FakeLocation();
  @override
  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async => const Coordinates(latitude: 36.0467649, longitude: -115.4071329);
}

void main() {
  test(
    'straight-line distance handles identical points and a known meridian arc',
    () {
      const origin = Coordinates(latitude: 0, longitude: 0);
      expect(
        CoolingActions.distanceMeters(origin, {'latitude': 0, 'longitude': 0}),
        0,
      );
      expect(
        CoolingActions.distanceMeters(origin, {'latitude': 1, 'longitude': 0}),
        closeTo(111195, 2),
      );
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'location, dialer, source and destination selection on $platform',
      (tester) async {
        final data = OfficialCoolingDirectory.parse(
          jsonDecode(
            File('data/cooling_centers/official_directory.json')
                .readAsStringSync(),
          ),
        );
        final actions = FakeActions();
        CoolingDestination? destination;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: OfficialCoolingPage(
                unofficialLoader: loadTestCommunityDirectory,
                discoveryAssetsLoader: loadTestDiscoveryAssets,
                loader: () async => data,
                actions: actions,
                locationService: const FakeLocation(),
                onDestinationSelected: (d) => destination = d,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(actions.dialed, isNull);
        expect(actions.opened, isNull);
        await tester.enterText(find.byType(TextField), '89004');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Blue Diamond');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byTooltip('Place details'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.byTooltip('Place details'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Place details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open phone dialer'));
        await tester.pumpAndSettle();
        expect(actions.dialed, isNotNull);
        await tester.scrollUntilVisible(
          find.textContaining('published records'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('published records'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('aug-en · en'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('aug-en · en'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('aug-en · en'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Open source'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Open source'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open source'));
        await tester.pumpAndSettle();
        expect(actions.opened, startsWith('https://www.clarkcountynv.gov/'));
        await tester.scrollUntilVisible(
          find.text('Select as planned destination'),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Select as planned destination'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select as planned destination'));
        await tester.pumpAndSettle();
        expect(destination!.id, 'blue-diamond-library');
        expect(destination!.location.latitude, 36.0467649);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShadeRoutePage(coolingDestination: destination),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.scrollUntilVisible(
          find.text('Planned cooling destination'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Blue Diamond Library'), findsOneWidget);
        expect(find.text('Shade route choices (demo)'), findsNothing);
        expect(find.textContaining('has not been calculated'), findsOneWidget);
      },
    );
  }
}
