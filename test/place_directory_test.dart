import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/place_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const near = CityTripService.planningCenter;
  const far = Coordinates(latitude: 36.22, longitude: -115.12);
  final local = [
    const CityPlace(
      'A different name',
      '123 Main Street',
      near,
      aliases: ['Café Test'],
    ),
    const CityPlace('Chain coffee', 'Another street', far),
    const CityPlace('Chain coffee', 'Near street', near),
  ];
  test(
    'bundled snapshot validates all records, IDs, source URLs and bounds',
    () async {
      final raw = jsonDecode(
        await rootBundle.loadString('data/places/las_vegas.json'),
      ) as Map;
      final places = PlaceDirectory.parse(raw);
      expect(places.length, raw['count']);
      expect(places.length, greaterThan(13000));
      expect(
        places.every((p) => CityTripService.isInPlanningArea(p.point)),
        true,
      );
      expect(places.map((p) => p.sourceUrl).toSet().length, places.length);
      expect(
        places.every(
          (p) => p.sourceUrl!.startsWith('https://www.openstreetmap.org/'),
        ),
        true,
      );
      expect(
        places.where((p) => p.name.toLowerCase().contains('starbucks')).length,
        greaterThan(20),
      );
      expect(
        places.any((p) => p.name.toLowerCase().contains('meadows school')),
        true,
      );
      expect(raw['license'], 'ODbL-1.0');
    },
  );
  test('local results work offline, rank near central Las Vegas and keep chain branches', () async {
    var requests = 0;
    final service = CityTripService(
      loadPlaces: () async => local,
      client: MockClient((_) async {
        requests++;
        throw Exception('offline');
      }),
    );
    addTearDown(service.client.close);
    final results = await service.search('Chain coffee');
    expect(results.length, 2);
    expect(results.first.address, 'Near street');
    expect(requests, 0);
    expect((await service.search('café test')).single.name, 'A different name');
    expect(
      (await service.search('123 Main')).single.address,
      '123 Main Street',
    );
  });
  test(
    'explicit online search supplements local matches without removing them',
    () async {
      var requests = 0;
      final service = CityTripService(
        loadPlaces: () async => local,
        client: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [-115.2, 36.19],
                  },
                  'properties': {'name': 'Another Chain coffee'},
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.client.close);
      expect((await service.search('Chain coffee')).length, 2);
      expect(requests, 0);
      expect(
        (await service.searchOnline('Chain coffee')).single.name,
        'Another Chain coffee',
      );
      expect(requests, 1);
      expect((await service.search('Chain coffee')).length, 2);
    },
  );
  test('live address search survives missing local assets', () async {
    final service = CityTripService(
      loadPlaces: () async => throw Exception('missing asset'),
      client: MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Some new address');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'type': 'Point',
                  'coordinates': [-115.28, 36.19],
                },
                'properties': {'name': 'Live result'},
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.client.close);
    expect(
      (await service.search('Some new address')).single.name,
      'Live result',
    );
  });
  test(
    'coordinate selection stays local and rejects outside destinations',
    () async {
      final service = CityTripService(
        loadPlaces: () async => throw Exception('not needed'),
        client: MockClient((_) async => throw Exception('must stay local')),
      );
      addTearDown(service.client.close);
      final place = (await service.search('36.194683, -115.2828654')).single;
      expect(place.point.latitude, 36.194683);
      expect(place.precision, 'user selected coordinates');
      await expectLater(service.search('40.0, -115.2'), throwsFormatException);
    },
  );
  test('malformed and out-of-area entries cannot become destinations', () {
    final result = PlaceDirectory.parse({
      'version': 1,
      'places': [
        {'name': 'No location'},
        {'name': 'Outside', 'latitude': 37, 'longitude': -115.2},
        {'name': 'Bad', 'latitude': double.nan, 'longitude': -115.2},
        {'name': 'Valid', 'latitude': 36.19, 'longitude': -115.2},
      ],
    });
    expect(result.single.name, 'Valid');
  });
}
