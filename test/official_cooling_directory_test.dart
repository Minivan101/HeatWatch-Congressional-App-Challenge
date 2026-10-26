import 'cooling_asset_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';
import 'package:heatwatch/features/cool_spots/presentation/official_cooling_page.dart';

Map<String, dynamic> fixture() => jsonDecode(
  File('data/cooling_centers/official_directory.json').readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  test(
    'all source records survive import, including original field values',
    () {
      final directory = OfficialCoolingDirectory.parse(fixture());
      final research = jsonDecode(
        File('data/cooling_centers/research/cooling-stations-research.json')
            .readAsStringSync(),
      ) as Map;
      final map = jsonDecode(
        File('data/cooling_centers/research/county-map-stations.json')
            .readAsStringSync(),
      ) as Map;
      expect(directory.stations.length, 45);
      expect(directory.data['assertionCount'], 353);
      expect(directory.data['review']['coordinateMatches'], 45);
      expect(directory.data['review']['addressMatches'], 45);
      expect(directory.data['review']['countyMapPins'], 0);
      final legion = directory.stations.singleWhere(
        (s) => s['id'] == 'american-legion',
      );
      expect(legion['phone'], '(702) 299-1510');
      expect(
        legion['phoneProvenance']['sourceUrl'],
        'https://www.nevadalegiond2.org/post-info',
      );
      expect(legion['assertions'][0]['phoneAsPrinted'], '(702) 565-5433');
      final gis = jsonDecode(
        File(
          'data/cooling_centers/research/sources/qr-county-layer-records.json',
        ).readAsStringSync(),
      ) as Map;
      final importedGis = directory.stations
          .expand((s) => s['assertions'] as List)
          .where((a) => a['sourceId'] == 'county-cooling-gis')
          .toList();
      expect(importedGis, hasLength(45));
      for (final feature in gis['features'] as List) {
        expect(
          importedGis.singleWhere(
            (a) =>
                a['originalFeature']['properties']['OBJECTID'] ==
                feature['properties']['OBJECTID'],
          )['originalFeature'],
          feature,
        );
      }
      expect(
        directory.data['sources'].expand((s) => s['qrLinks'] as List),
        hasLength(4),
      );
      expect(
        directory.stations.singleWhere(
          (s) => s['id'] == 'meadows-library',
        )['currentOpenStatus'],
        'unknown',
      );
      for (final original in [...research['records'], ...map['records']]) {
        final station = directory.stations.singleWhere(
          (s) => s['id'] == original['stationId'],
        );
        final imported = (station['assertions'] as List).singleWhere(
          (a) => a['sourceId'] == original['sourceId'],
        ) as Map;
        for (final key in original.keys) {
          expect(
            imported[key],
            original[key],
            reason: '${original['stationId']} $key',
          );
        }
      }
    },
  );

  test('unlisted days stay unknown; explicit weekend closure stays closed', () {
    final directory = OfficialCoolingDirectory.parse(fixture());
    final alexander = directory.stations.singleWhere(
      (s) => s['id'] == 'alexander-library',
    );
    final cambridge = directory.stations.singleWhere(
      (s) => s['id'] == 'cambridge-recreation-center',
    );
    expect(alexander['assertions'][0]['weeklyHours']['7'], isNull);
    expect(cambridge['assertions'][0]['weeklyHours']['7'], isEmpty);
    final blue = directory.stations.singleWhere(
      (s) => s['id'] == 'blue-diamond-library',
    );
    expect(blue['coordinates']['sourceKind'], 'official-facility');
    expect(
      blue['coordinateReview']['candidates'][0]['address'],
      '14 Cottonwood Dr',
    );
    expect(blue['assertions'][0]['weeklyHours']['3'][0]['endMinute'], 1140);
    expect(blue['assertions'][3]['weeklyHours']['3'][0]['endMinute'], 960);
    expect(blue['assertions'][1]['weeklyHours'], isNull);
    expect(blue['reviewNotes'], isNotEmpty);
  });

  test(
    'expired notices and ordinary facility hours never become open status',
    () {
      final directory = OfficialCoolingDirectory.parse(fixture());
      final courtyard = directory.stations.singleWhere(
        (s) => s['id'] == 'courtyard-homeless-resource-center',
      );
      expect(courtyard['currentOpenStatus'], 'unknown');
      expect(
        OfficialCoolingDirectory.periodLabel(
          courtyard['assertions'][0],
          DateTime.utc(2026, 10, 2),
        ),
        'Expired activation listing',
      );
      expect(
        OfficialCoolingDirectory.periodLabel(
          courtyard['assertions'][0],
          DateTime.utc(2026, 8, 19),
        ),
        'Listed period · opening unverified',
      );
      expect(
        OfficialCoolingDirectory.periodLabel(
          courtyard['assertions'][3],
          DateTime.utc(2026, 10, 2),
        ),
        'Activation dates not supplied',
      );
    },
  );

  test('updated sources preserve unknown activation and conflicting hours', () {
    final directory = OfficialCoolingDirectory.parse(fixture());
    expect(directory.revision, 5);
    for (final id in ['updated-2026-en', 'updated-2026-es']) {
      expect(directory.source(id)['activationStart'], isNull);
      expect(directory.source(id)['activationEnd'], isNull);
      expect(
        directory.stations
            .where(
              (s) => (s['assertions'] as List).any((a) => a['sourceId'] == id),
            )
            .length,
        44,
      );
    }
    final neighborhood = directory.stations.singleWhere(
      (s) => s['id'] == 'neighborhood-recreation-center',
    );
    final latest = (neighborhood['assertions'] as List).singleWhere(
      (a) => a['sourceId'] == 'updated-2026-en',
    );
    expect(latest['weeklyHours']['6'], isNull);
    final meadows = directory.stations.singleWhere(
      (s) => s['id'] == 'meadows-library',
    );
    expect(
      (meadows['assertions'] as List).any(
        (a) => a['sourceId'] == 'updated-2026-en',
      ),
      false,
    );
    expect(meadows['currentOpenStatus'], 'unknown');
    final windmill = directory.stations.singleWhere(
      (s) => s['id'] == 'windmill-library',
    );
    final map = (windmill['assertions'] as List).singleWhere(
      (a) => a['sourceId'] == 'county-resource-map-2026-10-11',
    );
    expect(
      map['descriptionAsDisplayed'],
      contains('limited quantity of free bus passes'),
    );
  });

  for (final corruption in [
    'date',
    'source',
    'count',
    'coordinate',
    'status',
    'hours',
  ]) {
    test('reject malformed $corruption before display or installation', () {
      final data = fixture();
      final station = data['stations'][0];
      switch (corruption) {
        case 'date':
          station['assertions'][0]['activationEnd'] = '2026-02-30';
        case 'source':
          data['sources'][0]['url'] = 'http://invalid.example';
        case 'count':
          data['assertionCount'] = 175;
        case 'coordinate':
          station['coordinates']['latitude'] = 999;
        case 'status':
          station['currentOpenStatus'] = 'open';
        case 'hours':
          station['assertions'][0]['weeklyHours']['1'][0]['endMinute'] = 2000;
      }
      expect(() => OfficialCoolingDirectory.parse(data), throwsFormatException);
    });
  }

  test(
    'invalid updates retain previous file; newer reviewed revision installs',
    () async {
      final temp = Directory.systemTemp.createTempSync('heatwatch-cooling-');
      try {
        final installed = File('${temp.path}/installed.json')
          ..writeAsStringSync(jsonEncode(fixture()));
        final previous = installed.readAsBytesSync();
        final candidate = File('${temp.path}/candidate.json');
        candidate.writeAsStringSync('{}');
        Future<ProcessResult> install() => Process.run('dart', [
          'scripts/validate_official_cooling.dart',
          candidate.path,
          '--install',
          installed.path,
        ]);
        expect((await install()).exitCode, 1);
        expect(installed.readAsBytesSync(), previous);
        candidate.writeAsStringSync(jsonEncode(fixture()));
        expect((await install()).exitCode, 1);
        expect(installed.readAsBytesSync(), previous);
        final next = fixture();
        next['revision'] = (next['revision'] as int) + 1;
        candidate.writeAsStringSync(jsonEncode(next));
        expect((await install()).exitCode, 0);
        expect(
          OfficialCoolingDirectory.parse(
            jsonDecode(installed.readAsStringSync()),
          ).revision,
          next['revision'],
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('offline search and report expose conflicts on $platform', (
      tester,
    ) async {
      final directory = OfficialCoolingDirectory.parse(fixture());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
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
      await tester.enterText(find.byType(TextField), '89004');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Blue Diamond');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Place details'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Place details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Place details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Published dates:'),
        findsNothing,
        reason:
            'The new undated flyer must precede the expired September flyer',
      );
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
      await tester.tap(find.text('aug-en · en'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Wed: 12:00pm-7:00pm'), findsOneWidget);
      expect(find.textContaining('Activation 2026-08'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
