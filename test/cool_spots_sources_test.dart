import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/presentation/cool_spots_page.dart';
import 'package:heatwatch/features/cool_spots/services/cool_spots_service.dart';
import 'package:heatwatch/features/cool_spots/models/cool_spots_contract.dart';

class _FakeCoolSpotsService extends CoolSpotsService {
  const _FakeCoolSpotsService(this.load, {this.centers});

  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) load;
  final Future<Map<String, dynamic>> Function()? centers;

  @override
  Future<Map<String, dynamic>> getLocalExample(Map<String, dynamic> location) =>
      load(location);

  @override
  Future<Map<String, dynamic>> getLocalCenters() => centers!();
}

void main() {
  late Map<String, dynamic> saved;
  setUpAll(() async {
    saved = {
      'dataset': jsonDecode(
        await rootBundle.loadString(
          'data/cooling_centers/clark_county_june_2026.json',
        ),
      ),
      'example': jsonDecode(
        await rootBundle.loadString('assets/cool_spots_demo.json'),
      ),
    };
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('past government centers stay separate from fictional business '
        'on $platform', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(body: CoolSpotsPage(dataLoader: () async => saved)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No open cooling center is verified.'), findsOneWidget);
      expect(find.text('Cambridge Recreation Center'), findsNothing);
      await tester.tap(find.text('View detailed report'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No current cooling-station activation'),
        findsOneWidget,
      );
      expect(find.text('Past official listings — inactive'), findsOneWidget);
      expect(find.text('Cambridge Recreation Center'), findsOneWidget);
      expect(find.text('Whitney Recreation Center'), findsOneWidget);
      expect(find.text('Fictional Cafe'), findsOneWidget);
      expect(find.textContaining('Opening status unknown'), findsOneWidget);
      expect(
        find.textContaining('straight-line from example point'),
        findsNWidgets(3),
      );
      expect(find.text('Copy county source link'), findsNWidgets(2));
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('empty source and business lists show separate gaps '
        'on $platform', (tester) async {
      final dataset = Map<String, dynamic>.from(saved['dataset'] as Map);
      final example = Map<String, dynamic>.from(saved['example'] as Map);
      dataset['centers'] = <dynamic>[];
      example['indoorPlaces'] = <dynamic>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: CoolSpotsPage(
              dataLoader: () async => {'dataset': dataset, 'example': example},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View detailed report'));
      await tester.pumpAndSettle();
      expect(
        find.text('No official records in this saved source.'),
        findsOneWidget,
      );
      expect(
        find.text('No indoor business examples available.'),
        findsOneWidget,
      );
    });

    testWidgets('load failure can retry saved data on $platform', (
      tester,
    ) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      Future<Map<String, dynamic>> load() {
        calls++;
        return calls == 1 ? pending.future : Future.value(saved);
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(body: CoolSpotsPage(dataLoader: load)),
        ),
      );
      expect(find.text('Loading saved places…'), findsOneWidget);
      pending.completeError(StateError('fixture unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saved place records could not be loaded.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry saved records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View detailed report'));
      await tester.pumpAndSettle();
      expect(find.text('Cambridge Recreation Center'), findsOneWidget);
    });
  }

  testWidgets('local Functions result is clearly fictional and retryable', (
    tester,
  ) async {
    var calls = 0;
    final service = _FakeCoolSpotsService((location) async {
      calls++;
      if (calls == 1) throw StateError('emulator unavailable');
      return {
        'sampleOnly': true,
        'checkedAt': '2026-06-21T16:00:00.000Z',
        'referenceLocation': location,
        'indoorPlaces': (saved['example'] as Map)['indoorPlaces'],
      };
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoolSpotsPage(dataLoader: () async => saved, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View detailed report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load local Cool Spots example'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Local Function unavailable'), findsOneWidget);
    await tester.tap(find.text('Load local Cool Spots example'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No Places API request was made'),
      findsOneWidget,
    );
    expect(find.textContaining('Fictional Cafe'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('county records can switch to a validated local backend copy', (
    tester,
  ) async {
    var calls = 0;
    final response = {
      'source': 'LOCAL_FIRESTORE_EMULATOR',
      'dataset': saved['dataset'],
      'localDate': '2026-09-28',
      'dateStatuses': {
        'cc-cambridge-june-2026': 'expired',
        'cc-whitney-june-2026': 'expired',
      },
    };
    final service = _FakeCoolSpotsService(
      (_) async => saved,
      centers: () async {
        calls++;
        if (calls == 1) throw StateError('emulator stopped');
        return CoolSpotsContract.localCenters(response);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoolSpotsPage(dataLoader: () async => saved, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View detailed report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bundled with the app'), findsOneWidget);
    await tester.ensureVisible(find.text('Read local center records'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read local center records'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Local center records unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Read local center records'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('from the local Firestore emulator'),
      findsOneWidget,
    );
    expect(find.text('Past official listings — inactive'), findsOneWidget);
    expect(calls, 2);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('malformed center source hides records on $platform', (
      tester,
    ) async {
      final invalid = Map<String, dynamic>.from(saved['dataset'] as Map);
      invalid['sourceUrl'] = 'http://invalid.example';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: CoolSpotsPage(
              dataLoader: () async => {
                'dataset': invalid,
                'example': saved['example'],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Saved place records could not be loaded.'),
        findsOneWidget,
      );
      expect(find.text('Cambridge Recreation Center'), findsNothing);
      expect(find.text('Retry saved records'), findsOneWidget);
    });
  }
}
