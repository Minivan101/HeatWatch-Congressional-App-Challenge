@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';
import 'package:heatwatch/core/saved_places/saved_places_store_web.dart';

@JS('globalThis.localStorage')
external _TestStorage get _storage;

extension type _TestStorage(JSObject _) implements JSObject {
  external void removeItem(String key);
}

void main() {
  test('real browser storage restores favorites, Home and Work across new instances', () async {
    final key = 'heatwatch.test.saved.${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => _storage.removeItem(key));
    final firstStore = SavedPlacesStore(key: key);
    final saved = SavedPlaces(read: firstStore.read, write: firstStore.write);
    await saved.load();
    const place = SavedPlace(
      name: 'Public library',
      address: 'Public test address',
      point: Coordinates(latitude: 36.17, longitude: -115.14),
      sourceUrl: 'https://www.openstreetmap.org/node/1',
      precision: 'mapped point',
    );
    await saved.toggleFavorite(place);
    await saved.setLabel(PlaceLabel.home, place);
    await saved.setLabel(PlaceLabel.work, place);
    saved.dispose();
    final nextStore = SavedPlacesStore(key: key);
    final restored = SavedPlaces(read: nextStore.read, write: nextStore.write);
    await restored.load();
    expect(restored.favorites.single.name, place.name);
    expect(restored.labeled(PlaceLabel.home)?.sourceUrl, place.sourceUrl);
    expect(restored.labeled(PlaceLabel.work)?.precision, place.precision);
    restored.dispose();
  });
  test('oversized browser writes fail explicitly', () async {
    final key =
        'heatwatch.test.saved.large.${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => _storage.removeItem(key));
    await expectLater(
      SavedPlacesStore(key: key).write('x' * (1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
