import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/models/cool_spots_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> dataset;
  late Map<String, dynamic> example;
  setUpAll(() async {
    dataset = jsonDecode(
      await rootBundle.loadString(
        'data/cooling_centers/clark_county_june_2026.json',
      ),
    ) as Map<String, dynamic>;
    example = jsonDecode(
      await rootBundle.loadString('assets/cool_spots_demo.json'),
    ) as Map<String, dynamic>;
  });

  test('government records reject mismatched source and impossible dates', () {
    expect(() => CoolSpotsContract.dataset(dataset), returnsNormally);
    final mismatched = jsonDecode(jsonEncode(dataset)) as Map<String, dynamic>;
    (mismatched['centers'] as List).first['sourceAgency'] = 'Fictional Cafe';
    expect(() => CoolSpotsContract.dataset(mismatched), throwsFormatException);
    final badDate = jsonDecode(jsonEncode(dataset)) as Map<String, dynamic>;
    (badDate['centers'] as List).first['validUntil'] = '2026-02-30';
    expect(() => CoolSpotsContract.dataset(badDate), throwsFormatException);
  });

  test('fictional business cannot claim real Places or verified opening', () {
    expect(() => CoolSpotsContract.fictionalPlaces(example), returnsNormally);
    final badSource = jsonDecode(jsonEncode(example)) as Map<String, dynamic>;
    (badSource['indoorPlaces'] as List).first['source'] = 'GOOGLE_PLACES';
    expect(
      () => CoolSpotsContract.fictionalPlaces(badSource),
      throwsFormatException,
    );
    final badOpen = jsonDecode(jsonEncode(example)) as Map<String, dynamic>;
    (badOpen['indoorPlaces'] as List).first['openNow'] = true;
    expect(
      () => CoolSpotsContract.fictionalPlaces(badOpen),
      throwsFormatException,
    );
  });

  test('local center statuses must match the source dates', () {
    final response = {
      'source': 'LOCAL_FIRESTORE_EMULATOR',
      'dataset': dataset,
      'localDate': '2026-06-05',
      'dateStatuses': {
        'cc-cambridge-june-2026': 'date-listed',
        'cc-whitney-june-2026': 'date-listed',
      },
    };
    expect(() => CoolSpotsContract.localCenters(response), returnsNormally);
    final bad = jsonDecode(jsonEncode(response)) as Map<String, dynamic>;
    bad['dateStatuses']['cc-whitney-june-2026'] = 'expired';
    expect(() => CoolSpotsContract.localCenters(bad), throwsFormatException);
  });

  test('date classification uses the supplied local day at boundaries', () {
    expect(
      CoolSpotsContract.classifyDates('2026-06-04', '2026-06-05', '2026-06-03'),
      'upcoming',
    );
    expect(
      CoolSpotsContract.classifyDates('2026-06-04', '2026-06-05', '2026-06-05'),
      'date-listed',
    );
    expect(
      CoolSpotsContract.classifyDates('2026-06-04', '2026-06-05', '2026-06-06'),
      'expired',
    );
  });
}
