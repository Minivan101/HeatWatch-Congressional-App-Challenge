import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SettingsStore {
  SettingsStore({this.directory});

  final Directory? directory;
  Future<File> _file() async => File(
    '${(directory ?? await getApplicationSupportDirectory()).path}/appearance-settings.json',
  );
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists() || await file.length() > 4096) return null;
    return file.readAsString();
  }

  Future<void> write(String value) async {
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
