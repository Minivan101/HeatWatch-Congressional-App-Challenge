import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'weather_cache_store.dart';

class WeatherCache implements WeatherCacheStore {
  WeatherCache({this.directoryProvider = getApplicationSupportDirectory});
  final Future<Directory> Function() directoryProvider;
  Future<File> _file() async =>
      File('${(await directoryProvider()).path}/latest-weather.json');
  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists() || await file.length() > 5 * 1024 * 1024) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String content) async {
    if (content.length > 5 * 1024 * 1024) {
      throw const FormatException('Cache too large');
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    final stage = File('${file.path}.staged');
    try {
      await stage.writeAsString(content, flush: true);
      await stage.rename(file.path);
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
