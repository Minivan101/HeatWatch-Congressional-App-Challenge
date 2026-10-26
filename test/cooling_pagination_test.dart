import 'cooling_asset_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/models/coordinates.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';

void main() {
  testWidgets(
    'ZIP changes preserve category and pagination shows more nearby places',
    (tester) async {
      final directory = OfficialCoolingDirectory.parse(
        jsonDecode(
          File('data/cooling_centers/official_directory.json')
              .readAsStringSync(),
        ),
      );
      final settings = AppSettings(read: () async => null, write: (_) async {});
      final location = AppLocation(settings);
      await settings.update(location: LocationChoice.everyOpen);
      location.position = const Coordinates(
        latitude: 36.19,
        longitude: -115.28,
      );
      await tester.pumpWidget(
        LocationScope(
          location: location,
          child: MaterialApp(
            home: Scaffold(
              body: OfficialCoolingPage(
                unofficialLoader: loadTestCommunityDirectory,
                discoveryAssetsLoader: loadTestDiscoveryAssets,
                loader: () async => directory,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '89128');
      await tester.pumpAndSettle();
      final more = find.textContaining('Show more (');
      await tester.scrollUntilVisible(
        more,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Libraries'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Libraries'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '89119');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Libraries'))
            .selected,
        isTrue,
      );
      expect(find.textContaining('within 5 miles of 89119'), findsOneWidget);
      Future<void> selectRadius(int miles) async {
        final dropdown = find.byKey(const ValueKey('cooling-radius'));
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Within $miles miles').last);
        await tester.pumpAndSettle();
      }

      await selectRadius(10);
      expect(find.textContaining('within 10 miles of 89119'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '89135');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('cooling-radius')),
            )
            .value,
        10,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Libraries'))
            .selected,
        isTrue,
      );
      await selectRadius(15);
      expect(find.textContaining('within 15 miles of 89135'), findsOneWidget);
      await selectRadius(5);
      expect(find.textContaining('within 5 miles of 89135'), findsOneWidget);
      expect(find.textContaining('All Clark County'), findsNothing);
      expect(find.text('Official'), findsNothing);
      expect(find.text('Unofficial'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      location.dispose();
      settings.dispose();
    },
  );
}
