import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';

const park = SavedPlace(
  name: 'Public Park',
  address: '100 Test Street',
  point: Coordinates(latitude: 36.17, longitude: -115.14),
  sourceUrl: 'https://www.openstreetmap.org/node/100',
  precision: 'mapped point',
);
const library = SavedPlace(
  name: 'Public Library',
  address: '200 Test Street',
  point: Coordinates(latitude: 36.18, longitude: -115.14),
  sourceUrl: 'https://www.openstreetmap.org/node/200',
  precision: 'mapped point',
);
void main() {
  test('favorites, labels and provenance survive restart; removal keeps Home and Work independent', () async {
    String? disk;
    final saved = SavedPlaces(
      read: () async => disk,
      write: (s) async => disk = s,
    );
    await saved.load();
    await saved.toggleFavorite(park);
    await saved.setLabel(PlaceLabel.home, park);
    await saved.setLabel(PlaceLabel.work, park);
    await saved.rename(park, 'My park');
    final restored = SavedPlaces(
      read: () async => disk,
      write: (s) async => disk = s,
    );
    await restored.load();
    expect(restored.favorites.single.title, 'My park');
    expect(restored.labeled(PlaceLabel.home)?.sourceUrl, park.sourceUrl);
    expect(restored.labeled(PlaceLabel.work)?.precision, 'mapped point');
    final renamed = SavedPlace.fromDestination(
      restored.favorites.single.destination,
    );
    await restored.toggleFavorite(renamed);
    expect(restored.favorites, isEmpty);
    expect(restored.labeled(PlaceLabel.home)?.title, 'My park');
    await restored.setLabel(PlaceLabel.home, library);
    expect(restored.labeled(PlaceLabel.work)?.title, 'My park');
    await restored.setLabel(PlaceLabel.work, null);
    final data = jsonDecode(disk!) as Map;
    expect((data['places'] as List).length, 1);
    expect(restored.labeled(PlaceLabel.home)?.name, library.name);
  });
  test(
    'hearts remain consistent after choosing a renamed saved place',
    () async {
      final saved = SavedPlaces(read: () async => null, write: (_) async {});
      await saved.load();
      await saved.toggleFavorite(park);
      await saved.rename(park, 'Lunch break');
      final selected = SavedPlace.fromCity(saved.favorites.single.cityPlace);
      expect(saved.isFavorite(selected), true);
      await saved.toggleFavorite(selected);
      expect(saved.favorites, isEmpty);
    },
  );
  test(
    'write failure is visible and retry saves the latest ordered changes',
    () async {
      var fail = true;
      String? disk;
      final saved = SavedPlaces(
        read: () async => null,
        write: (s) async {
          if (fail) throw StateError('storage unavailable');
          disk = s;
        },
      );
      await saved.load();
      await saved.toggleFavorite(park);
      expect(saved.error, contains('could not be saved'));
      expect(saved.favorites.single.name, park.name);
      fail = false;
      await saved.retrySave();
      expect(saved.error, isNull);
      final restored = SavedPlaces(read: () async => disk, write: (_) async {});
      await restored.load();
      expect(restored.favorites.single.name, park.name);
      await Future.wait([
        saved.setLabel(PlaceLabel.home, park),
        saved.setLabel(PlaceLabel.home, library),
      ]);
      final latest = SavedPlaces(read: () async => disk, write: (_) async {});
      await latest.load();
      expect(latest.labeled(PlaceLabel.home)?.name, library.name);
    },
  );
  test(
    'failed restoration cannot overwrite existing storage and can be retried',
    () async {
      var bad = true, writes = 0;
      final saved = SavedPlaces(
        read: () async => bad ? 'damaged' : null,
        write: (_) async => writes++,
      );
      await saved.load();
      expect(saved.restoreFailed, true);
      await saved.toggleFavorite(park);
      expect(writes, 0);
      bad = false;
      await saved.load();
      expect(saved.restoreFailed, false);
      await saved.toggleFavorite(park);
      expect(writes, 1);
    },
  );
  test(
    'malformed locations and dangling labels do not become route endpoints',
    () async {
      final valid = park.toJson();
      final saved = SavedPlaces(
        read: () async => jsonEncode({
          'version': 1,
          'places': [
            valid,
            {...valid, 'latitude': 100},
            {'name': 'Missing coordinates'},
          ],
          'favoriteIds': [park.id, 'missing'],
          'homeId': 'missing',
          'workId': park.id,
        }),
        write: (_) async {},
      );
      await saved.load();
      expect(saved.favorites.length, 1);
      expect(saved.labeled(PlaceLabel.home), isNull);
      expect(saved.labeled(PlaceLabel.work)?.name, park.name);
    },
  );
  test(
    'buttons cannot overwrite saved data before a delayed load completes',
    () async {
      final read = Completer<String?>();
      var writes = 0;
      final saved = SavedPlaces(
        read: () => read.future,
        write: (_) async => writes++,
      );
      final loading = saved.load();
      await saved.toggleFavorite(park);
      expect(writes, 0);
      read.complete(null);
      await loading;
      await saved.toggleFavorite(park);
      expect(writes, 1);
    },
  );
}
