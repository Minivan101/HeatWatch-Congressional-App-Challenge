import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_area.dart';

void main() {
  test('saved Las Vegas focus includes pilot-area libraries and excludes distant county locations', () {
    final data = jsonDecode(
      File('data/cooling_centers/official_directory.json').readAsStringSync(),
    ) as Map;
    final stations = (data['stations'] as List).cast<Map<String, dynamic>>();
    final names = stations.where(isLasVegasArea).map((s) => s['name']).toSet();
    expect(names.length, 19);
    expect(
      names,
      containsAll([
        'Meadows Library',
        'Summerlin Library',
        'Cambridge Recreation Center',
        'Hollywood Recreation Center',
      ]),
    );
    for (final name in [
      'Mount Charleston Library',
      'Blue Diamond Library',
      'Laughlin Library',
      'West Henderson Library',
      'Alexander Library',
    ]) {
      expect(names, isNot(contains(name)));
    }
    expect(stations.length, 45);
  });
  test('unknown or misleading street names cannot imply Las Vegas area', () {
    expect(
      isLasVegasArea({'name': 'Test', 'address': 'Las Vegas Blvd'}),
      false,
    );
    expect(
      isLasVegasArea({'name': 'Test', 'address': '123 Main, 89102-1234'}),
      true,
    );
    expect(
      isLasVegasArea({'name': 'Test', 'address': '123 Main, 189102'}),
      false,
    );
    expect(isLasVegasArea({}), false);
  });
}
