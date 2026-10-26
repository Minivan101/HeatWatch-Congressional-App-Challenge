import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

class SavedPlacesStore {
  SavedPlacesStore({this.directory});
  final Directory? directory;
  Future<File> _file() async => File(
    '${(directory ?? await getApplicationSupportDirectory()).path}/saved-places.json',
  );
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('Saved places file is too large');
    }
    return file.readAsString();
  }

  Future<void> write(String value) async {
    if (utf8.encode(value).length > 1024 * 1024) {
      throw const FormatException('Saved places exceed the storage limit');
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.staged');
    try {
      await staged.writeAsString(value, flush: true);
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }
}
