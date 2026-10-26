import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_discovery.dart';
import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';

void main() {
  final data = jsonDecode(
    File('data/cooling_centers/unofficial_directory.json').readAsStringSync(),
  );
  final directory = UnofficialCoolingDirectory.parse(data);
  final photos = jsonDecode(
    File('assets/cool_spots/photos.json').readAsStringSync(),
  ) as Map;
  final zip =
      jsonDecode(
            File('assets/cool_spots/zip_points.json').readAsStringSync(),
          )['points']['89119']
          as List;
  final center = Coordinates(
    latitude: (zip[0] as num).toDouble(),
    longitude: (zip[1] as num).toDouble(),
  );

  test(
    'large indoor destinations widen the search without losing distance order',
    () {
      final expected = {5: 8, 10: 14, 15: 18};
      for (final miles in coolingRadiusChoices) {
        final places = nearbyCoolingPlaces(
          directory.places,
          center,
          category: 'Indoor Places',
          radiusMiles: miles,
        );
        expect(places.length, expected[miles]);
        expect(places.first['name'], 'Town Square Las Vegas');
        if (miles == 15) {
          expect(
            places.map((p) => p['name']),
            containsAll([
              'Red Rock Resort',
              'Downtown Summerlin',
              'Las Vegas South Premium Outlets',
            ]),
          );
        } else {
          expect(
            places.map((p) => p['name']),
            isNot(contains('Red Rock Resort')),
          );
        }
      }
    },
  );

  test(
    'open-air districts never claim whole-property AC or unverified water',
    () {
      final additions = directory.places.where(
        (p) => p['kind'] == 'indoorDestination',
      );
      expect(additions.length, 17);
      for (final place in additions) {
        expect(coolingCategory(place), 'Indoor Places');
        expect(place['methods'], isNot(contains('drinkingWater')));
        expect(photos[place['id']]['amenities'], contains('food'));
        expect(place['access'], isNot(contains('cost')));
        expect(place['officialCoolingStation'], false);
        if ([
          'Town Square Las Vegas',
          'Downtown Summerlin',
        ].contains(place['name'])) {
          expect(place['methods'], ['indoorVenues']);
          expect(place['scopeLabel'], contains('outdoor walkways'));
        }
        if ((place['scopeLabel'] as String? ?? '').contains('non-gaming')) {
          expect(place['access'], contains('Gaming floors'));
        }
      }
    },
  );

  test('unsupported indoor scope and conflicting AC claims are rejected', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (p) => p['evidence']['scopeSource'] = 'http://invalid.example',
      (p) => p['evidence']['coolingScope'] = '',
      (p) => p['methods'] = ['indoorVenues', 'airConditioning'],
    ]) {
      final changed = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
      final place = (changed['places'] as List).firstWhere(
        (p) => p['name'] == 'Town Square Las Vegas',
      ) as Map<String, dynamic>;
      mutate(place);
      expect(
        () => UnofficialCoolingDirectory.parse(changed),
        throwsFormatException,
      );
    }
  });
}
