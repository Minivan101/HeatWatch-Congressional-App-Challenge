import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/saved_places/saved_places.dart';
import 'package:heatwatch/core/saved_places/saved_places_store_file.dart';

void main() {
  test('native restart restores a list larger than appearance preferences and leaves that file alone', () async {
    final directory = await Directory.systemTemp.createTemp(
      'heatwatch-saved-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final appearance = File('${directory.path}/appearance-settings.json');
    await appearance.writeAsString('{"location":"never"}');
    final store = SavedPlacesStore(directory: directory);
    final saved = SavedPlaces(read: store.read, write: store.write);
    await saved.load();
    for (var i = 0; i < 40; i++) {
      await saved.toggleFavorite(
        SavedPlace(
          name: 'Public place $i',
          address: '$i Test Street',
          point: Coordinates(latitude: 36.17 + i / 10000, longitude: -115.14),
          sourceUrl: 'https://www.openstreetmap.org/node/$i',
          precision: 'mapped point',
        ),
      );
    }
    expect((await store.read())!.length, greaterThan(4096));
    final restored = SavedPlaces(read: store.read, write: store.write);
    await restored.load();
    expect(restored.favorites.length, 40);
    expect(await appearance.readAsString(), '{"location":"never"}');
    expect(
      await File('${directory.path}/saved-places.json.staged').exists(),
      false,
    );
  });
}
