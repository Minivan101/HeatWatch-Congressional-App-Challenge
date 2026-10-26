import 'cooling_asset_support.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/core/models/coordinates.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/settings/app_settings.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_directory_repository.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_destination.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/presentation/route_weather_panel.dart';

class ThrowingDirectory extends CoolingDirectoryRepository {
  ThrowingDirectory(this.directory);
  final OfficialCoolingDirectory directory;
  int calls = 0;
  @override
  Future<CoolingSnapshot> load() async =>
      CoolingSnapshot(directory, 'Test saved records');
  @override
  Future<CoolingSnapshot> refresh() async {
    calls++;
    if (calls == 1) throw StateError('unexpected storage failure');
    return CoolingSnapshot(directory, 'Test saved records');
  }
}

class ThrowingCache extends WeatherRepository {
  @override
  Future<FreeWeatherResult?> cachedFor(WeatherPlace place) async =>
      throw StateError('cache failure');
}

void main() {
  final directory = OfficialCoolingDirectory.parse(
    jsonDecode(
      File('data/cooling_centers/official_directory.json').readAsStringSync(),
    ),
  );
  testWidgets('multi-word directory search and clear recover an empty result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfficialCoolingPage(
            unofficialLoader: loadTestCommunityDirectory,
            discoveryAssetsLoader: loadTestDiscoveryAssets,
            loader: () async => directory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '89102');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Meadows 89102');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Meadows Library'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Meadows Library'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'no-such-facility');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.textContaining('Search a ZIP or city'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Meadows');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search a ZIP or city'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unexpected update failure keeps saved records and permits retry',
    (tester) async {
      final repo = ThrowingDirectory(directory);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficialCoolingPage(
              unofficialLoader: loadTestCommunityDirectory,
              discoveryAssetsLoader: loadTestDiscoveryAssets,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('About nearby places'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('About nearby places'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check directory updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check directory updates'));
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      await tester.scrollUntilVisible(
        find.text('Retry check'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Directory update failed. Saved locations remain available.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Retry check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry check'));
      await tester.pumpAndSettle();
      expect(repo.calls, 2);
      expect(
        find.text('Directory update failed. Saved locations remain available.'),
        findsNothing,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('trip cache failure is visible and leaves live check available', (
    tester,
  ) async {
    const destination = CoolingDestination(
      id: 'test',
      name: 'Test station',
      address: 'Test',
      location: Coordinates(latitude: 36.2, longitude: -115.2),
      precision: 'unverified',
      sourceUrl: 'https://example.org',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteWeatherPanel(
              destination: destination,
              repository: ThrowingCache(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alerts not checked'), findsOneWidget);
    expect(
      find.text('Trip update incomplete · retry available'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'older failed save cannot replace the newest preference status',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      var writes = 0;
      final settings = AppSettings(
        read: () async => null,
        write: (_) => ++writes == 1 ? first.future : second.future,
      );
      final oldSave = settings.update(theme: ThemeMode.dark);
      final newSave = settings.update(
        theme: ThemeMode.light,
        useFahrenheit: true,
      );
      await Future<void>.delayed(Duration.zero);
      first.completeError(StateError('old save failure'));
      await oldSave;
      expect(settings.saveError, isNull);
      expect(settings.themeMode, ThemeMode.light);
      second.complete();
      await newSave;
      expect(settings.saveError, isNull);
    },
  );
}
