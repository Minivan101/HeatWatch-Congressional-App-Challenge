import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_discovery.dart';

void main() {
  final saved = jsonDecode(
    File('assets/cool_spots/zip_points.json').readAsStringSync(),
  ) as Map;
  final p = saved['points']['89119'] as List;
  final center = Coordinates(
    latitude: (p[0] as num).toDouble(),
    longitude: (p[1] as num).toDouble(),
  );
  Map<String, dynamic> library(String id, String zip, double miles) => {
    'id': id,
    'name': '$id Library',
    'address': '1 Example Rd, Las Vegas NV $zip',
    'coordinates': {
      'latitude': center.latitude + miles * 1609.344 / 111194.9266,
      'longitude': center.longitude,
    },
  };
  test('each supported radius includes only its straight-line boundary', () {
    final records = [
      library('close', '89109', 2),
      library('middle', '89123', 9.99),
      library('wide', '89135', 14.99),
      library('outside', '89135', 15.01),
    ];
    for (final miles in coolingRadiusChoices) {
      expect(
        nearbyCoolingPlaces(
          records,
          center,
          radiusMiles: miles,
        ).map((p) => p['id']),
        miles == 5
            ? ['close']
            : miles == 10
            ? ['close', 'middle']
            : ['close', 'middle', 'wide'],
      );
    }
    expect(
      () => nearbyCoolingPlaces(records, center, radiusMiles: 20),
      throwsArgumentError,
    );
  });
  test('ZIP radius crosses address ZIP boundaries and sorts distance', () {
    final result = nearbyCoolingPlaces([
      library('far-own-zip', '89119', 4),
      library('near-neighbor', '89109', 2),
      library('outside', '89119', 5.01),
      library('edge', '89109', 4.999),
    ], center);
    expect(result.map((p) => p['id']), [
      'near-neighbor',
      'far-own-zip',
      'edge',
    ]);
  });
  test(
    'category eligibility excludes untyped facilities and missing points',
    () {
      final records = [
        library('near', '89109', 2),
        {
          'id': 'casino',
          'name': 'Gaming floor',
          'coordinates': {
            'latitude': center.latitude,
            'longitude': center.longitude,
          },
        },
        {'id': 'unknown', 'name': 'Unknown Library', 'coordinates': null},
      ];
      expect(
        nearbyCoolingPlaces(records, center, category: 'Libraries').length,
        1,
      );
      expect(nearbyCoolingPlaces(records, center, category: 'Parks'), isEmpty);
    },
  );
  test('Census ZIP point is valid and facility taxonomy is independent of designation', () {
    expect(center.latitude, inInclusiveRange(36.05, 36.15));
    expect(center.longitude, inInclusiveRange(-115.2, -115.05));
    expect(coolingCategory({'name': 'Pearson Community Center'}), 'Community');
    expect(
      coolingCategory({
        'name': 'Park',
        'kind': 'park',
        'methods': ['drinkingWater'],
      }),
      'Parks',
    );
    expect(
      coolingCategory({'name': 'Outlet', 'kind': 'mall'}),
      'Indoor Places',
    );
  });
}
