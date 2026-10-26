import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/cool_spots/models/cooling_discovery.dart';
import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';

void main() {
  final curated = jsonDecode(
    File('data/cooling_centers/additional_destinations.json')
        .readAsStringSync(),
  ) as Map;
  final directory = UnofficialCoolingDirectory.parse(
    jsonDecode(
      File('data/cooling_centers/unofficial_directory.json').readAsStringSync(),
    ),
  );
  final photos = jsonDecode(
    File('assets/cool_spots/photos.json').readAsStringSync(),
  ) as Map;

  test('ten reviewed facilities survive import with their evidence intact', () {
    final additions = (curated['places'] as List).cast<Map<String, dynamic>>();
    expect(additions, hasLength(10));
    for (final place in additions) {
      expect(
        directory.places.singleWhere((p) => p['id'] == place['id']),
        place,
      );
      expect(place['officialCoolingStation'], false);
      expect(place['methods'], ['airConditioning']);
      expect(place['evidence']['reviewedOn'], '2026-10-20');
      expect(place['coordinates']['precision'], isNotEmpty);
      for (final id in place['sourceIds']) {
        expect(Uri.parse(directory.source(id)['url']).scheme, 'https');
      }
      final photo = photos[place['id']] as Map;
      expect(File(photo['asset']).existsSync(), true);
      expect(photo['photoCredit'], isNotEmpty);
      expect(photo['photoLicense'], isNotEmpty);
      expect(photo['amenities'], isNot(contains('water')));
      expect(photo['displayAddress'], place['address']);
    }
    for (final id in ['aliante', 'santa-fe']) {
      final place = additions.singleWhere(
        (p) => p['id'] == 'community-added-$id',
      );
      expect(place['access'], contains('Gaming floors'));
      expect(place['access'], contains('guest-only'));
      expect(place['hours'], isNull);
      expect(coolingCategory(place), 'Indoor Places');
    }
  });

  test(
    'new neighborhood centers appear in Community near their mapped sites',
    () {
      for (final id in ['desert-breeze', 'silverado-ranch', 'mountain-crest']) {
        final place = directory.places.singleWhere(
          (p) => p['id'] == 'community-added-$id',
        );
        final point = place['coordinates'] as Map;
        final nearby = nearbyCoolingPlaces(
          directory.places,
          Coordinates(
            latitude: point['latitude'],
            longitude: point['longitude'],
          ),
          category: 'Community',
        );
        expect(nearby.first['id'], place['id']);
        expect(place['hours'], isNotEmpty);
      }
      final wetlands = directory.places.singleWhere(
        (p) => p['id'] == 'community-added-wetlands',
      );
      expect(wetlands['scopeLabel'], 'Indoor lounge & galleries');
      expect(wetlands['hours'], 'Tuesday–Sunday 9 am–3 pm; Monday closed.');
      expect(coolingCategory(wetlands), 'Indoor Places');
    },
  );

  test('Creative Commons photographs retain attribution and license links', () {
    for (final id in ['aliante', 'grand-canal', 'miracle-mile']) {
      final photo = photos['community-added-$id'];
      expect(
        photo['photoSource'],
        startsWith('https://commons.wikimedia.org/'),
      );
      expect(
        photo['photoLicenseUrl'],
        startsWith('https://creativecommons.org/'),
      );
      expect(photo['photoCredit'], isNotEmpty);
      expect(photo['modifications'], contains('no content changes'));
    }
  });
}
