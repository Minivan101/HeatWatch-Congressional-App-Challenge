import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_discovery.dart';

void main() {
  test('all eligible bundled facilities have real image files and source provenance', () {
    final photos = jsonDecode(
      File('assets/cool_spots/photos.json').readAsStringSync(),
    ) as Map;
    final places = <Map<String, dynamic>>[
      ...(jsonDecode(
                File('data/cooling_centers/official_directory.json')
                    .readAsStringSync(),
              )['stations']
              as List)
          .cast<Map<String, dynamic>>(),
      ...(jsonDecode(
                File('data/cooling_centers/unofficial_directory.json')
                    .readAsStringSync(),
              )['places']
              as List)
          .cast<Map<String, dynamic>>(),
    ];
    final eligible = places.where((p) => coolingCategory(p) != null);
    expect(eligible.length, 110);
    for (final place in eligible) {
      final record = photos[place['id']] as Map;
      expect(Uri.parse(record['photoSource'] as String).scheme, 'https');
      expect(Uri.parse(record['photoUrl'] as String).scheme, 'https');
      final bytes = File(record['asset'] as String).readAsBytesSync();
      expect(bytes.length, greaterThan(1000));
      expect(
        bytes.take(2).toList(),
        anyOf([
          equals([0xff, 0xd8]),
          equals([0x89, 0x50]),
        ]),
      );
    }
  });
}
