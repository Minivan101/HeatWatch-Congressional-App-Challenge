import 'cooling_asset_support.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service_test.dart' show FakeLocationClient;

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/widgets/home_shell.dart';

class TestPosition extends LocationService {
  TestPosition({this.pending});
  final Completer<Coordinates>? pending;
  int calls = 0;
  @override
  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async {
    calls++;
    return pending == null
        ? const Coordinates(latitude: 36.19, longitude: -115.28)
        : pending!.future;
  }
}

class PermissionCounter extends FakeLocationClient {
  PermissionCounter()
    : super(
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.denied,
      );
  int prompts = 0;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return super.requestPermission();
  }
}

void main() {
  test('never reads no GPS; session choice persists without extending access; every opening persists', () async {
    String? saved;
    final settings = AppSettings(
      read: () async => saved,
      write: (v) async => saved = v,
    );
    final service = TestPosition();
    final location = AppLocation(settings, service: service);
    await location.choose(LocationChoice.never);
    await location.refresh();
    expect(service.calls, 0);
    expect(location.position, isNull);
    await location.choose(LocationChoice.session);
    expect(service.calls, 1);
    expect(location.position, isNotNull);
    final restored = AppSettings(read: () async => saved, write: (_) async {});
    await restored.load();
    expect(restored.locationChoice, LocationChoice.session);
    final restarted = AppLocation(restored, service: service);
    await restarted.refresh();
    expect(service.calls, 1);
    expect(restarted.position, isNull);
    expect(restarted.choiceLabel, 'Session ended');
    await location.choose(LocationChoice.everyOpen);
    await location.refresh();
    expect(service.calls, 3);
    await restored.load();
    expect(restored.locationChoice, LocationChoice.everyOpen);
    await location.choose(LocationChoice.never);
    expect(location.position, isNull);
  });
  test('automatic refresh and restart never repeat a denied device permission prompt', () async {
    String? saved;
    final settings = AppSettings(
      read: () async => saved,
      write: (value) async => saved = value,
    );
    final client = PermissionCounter();
    final service = LocationService(client: client);
    final location = AppLocation(settings, service: service);
    await location.choose(LocationChoice.everyOpen);
    expect(client.prompts, 1);
    for (var n = 0; n < 3; n++) {
      await location.refresh();
    }
    expect(client.prompts, 1);
    expect(client.readPosition, isFalse);
    final restored = AppSettings(read: () async => saved, write: (_) async {});
    await restored.load();
    final restarted = AppLocation(restored, service: service);
    await restarted.refresh();
    expect(client.prompts, 1);
    expect(restored.locationChoice, LocationChoice.everyOpen);

    await restarted.choose(LocationChoice.everyOpen);
    expect(client.prompts, 2);
    location.dispose();
    restarted.dispose();
  });

  testWidgets('overlapping location-choice calls display a single dialog', (
    tester,
  ) async {
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final location = AppLocation(settings, service: TestPosition());
    final choices = <Future<void>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              choices.add(showLocationChoice(context, location));
              choices.add(showLocationChoice(context, location));
            },
            child: const Text('Choose'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Use your location?'), findsOneWidget);
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    await Future.wait(choices);
    expect(location.choice, LocationChoice.never);
    expect(find.text('Use your location?'), findsNothing);
    location.dispose();
  });

  testWidgets(
    'restored session choice does not reopen the popup across tabs or cold launches',
    (tester) async {
      String? saved;
      final settings = AppSettings(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      final first = AppLocation(settings, service: TestPosition());
      await first.choose(LocationChoice.session);
      for (var launch = 0; launch < 2; launch++) {
        final restored = AppSettings(
          read: () async => saved,
          write: (_) async {},
        );
        await restored.load();
        final service = TestPosition();
        final location = AppLocation(restored, service: service);
        await tester.runAsync(() async {
          await tester.pumpWidget(
            SettingsScope(
              settings: restored,
              child: LocationScope(
                location: location,
                child: const MaterialApp(
                  home: HomeShell(mapTilesEnabled: false),
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump(const Duration(seconds: 1));
        for (final label in ['CoolSpots', 'Home', 'ShadeMap']) {
          await tester.tap(find.text(label));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('Use your location?'), findsNothing);
        }
        expect(service.calls, 0);
        expect(find.textContaining('Session ended'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        location.dispose();
        restored.dispose();
      }
      first.dispose();
      settings.dispose();
    },
  );

  test('late GPS result cannot undo never choice', () async {
    final pending = Completer<Coordinates>();
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final location = AppLocation(
      settings,
      service: TestPosition(pending: pending),
    );
    final finding = location.choose(LocationChoice.session);
    await location.choose(LocationChoice.never);
    pending.complete(const Coordinates(latitude: 36.19, longitude: -115.28));
    await finding;
    expect(location.position, isNull);
    expect(location.choice, LocationChoice.never);
  });
  testWidgets('popup exposes all three choices and remembers never', (
    tester,
  ) async {
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final location = AppLocation(settings, service: TestPosition());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLocationChoice(context, location),
            child: const Text('Choose'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Every time I open the app'), findsOneWidget);
    expect(find.text('Just this session'), findsOneWidget);
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    expect(location.choice, LocationChoice.never);
    expect(location.position, isNull);
  });
  testWidgets(
    'shared location supplies list and report distances and never clears both',
    (tester) async {
      final data = OfficialCoolingDirectory.parse(
        jsonDecode(
          File('data/cooling_centers/official_directory.json')
              .readAsStringSync(),
        ),
      );
      final settings = AppSettings(read: () async => null, write: (_) async {});
      final location = AppLocation(settings, service: TestPosition());
      await location.choose(LocationChoice.session);
      await tester.pumpWidget(
        LocationScope(
          location: location,
          child: MaterialApp(
            home: Scaffold(
              body: OfficialCoolingPage(
                unofficialLoader: loadTestCommunityDirectory,
                discoveryAssetsLoader: loadTestDiscoveryAssets,
                loader: () async => data,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sort near me'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Summerlin Library');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Place details'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('mi · Libraries'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Place details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Place details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('mi from your location · straight-line'),
        findsOneWidget,
      );
      await location.choose(LocationChoice.never);
      await tester.pumpAndSettle();
      expect(find.textContaining('mi from your location'), findsNothing);
      expect(
        find.text('Distance: enable location in Settings'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.textContaining('mi · Libraries'), findsNothing);
    },
  );
}
