import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/settings/settings_sheet.dart';
import 'package:heatwatch/core/settings/why_heatwatch_page.dart';

import 'shared_location_test.dart' show TestPosition;

void main() {
  for (final large in [false, true]) {
    testWidgets(
      'Settings Why opens, scrolls and returns without changing location/preferences; large=$large',
      (tester) async {
        tester.view.physicalSize = Size(large ? 320 : 390, 650);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettings(
          read: () async => null,
          write: (_) async {},
        );
        final gps = TestPosition();
        final location = AppLocation(settings, service: gps);
        await location.choose(LocationChoice.never);
        final previousUnits = settings.fahrenheit;
        await tester.pumpWidget(
          LocationScope(
            location: location,
            child: MaterialApp(
              theme: ThemeData(
                brightness: large ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: Scaffold(body: SettingsSheet(settings: settings)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Why'));
        await tester.tap(find.text('Why'));
        await tester.pumpAndSettle();
        expect(find.byType(WhyHeatWatchPage), findsOneWidget);
        expect(find.text('Why HeatWatch'), findsOneWidget);
        for (final heading in [
          'People experiencing homelessness',
          'Health & community sources',
        ]) {
          await tester.scrollUntilVisible(
            find.text(heading),
            400,
            maxScrolls: 150,
            scrollable: find
                .descendant(
                  of: find.byType(WhyHeatWatchPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(find.text(heading));
          await tester.pumpAndSettle();
          expect(find.text(heading).hitTestable(), findsOneWidget);
          expect(tester.takeException(), null);
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(WhyHeatWatchPage), findsNothing);
        expect(find.byType(SettingsSheet), findsOneWidget);
        expect(location.choice, LocationChoice.never);
        expect(gps.calls, 0);
        expect(settings.fahrenheit, previousUnits);
        await tester.pumpWidget(const SizedBox());
        location.dispose();
        settings.dispose();
      },
    );
  }
}
