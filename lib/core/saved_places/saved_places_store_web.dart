import 'dart:js_interop';

@JS('globalThis.localStorage')
external _PlaceStorage get _storage;

extension type _PlaceStorage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

class SavedPlacesStore {
  SavedPlacesStore({this.key = 'heatwatch.saved-places.v1'});
  final String key;
  Future<String?> read() async {
    final value = _storage.getItem(key);
    if (value != null && value.length > 1024 * 1024) {
      throw const FormatException('Saved places exceed the storage limit');
    }
    return value;
  }

  Future<void> write(String value) async {
    if (value.length > 1024 * 1024) {
      throw const FormatException('Saved places exceed the storage limit');
    }
    _storage.setItem(key, value);
  }
}
