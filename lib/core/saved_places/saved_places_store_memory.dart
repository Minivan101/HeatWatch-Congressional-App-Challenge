class SavedPlacesStore {
  static String? _value;
  Future<String?> read() async => _value;
  Future<void> write(String value) async => _value = value;
}
