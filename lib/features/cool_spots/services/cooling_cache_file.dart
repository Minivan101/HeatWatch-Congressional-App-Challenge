import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cooling_cache_store.dart';

class CoolingCache implements CoolingCacheStore {
  CoolingCache({this.directoryProvider = getApplicationSupportDirectory});
  final Future<Directory> Function() directoryProvider;

  Future<File> _file() async => File(
    '${(await directoryProvider()).path}/official-cooling-directory.json',
  );

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    if (await file.length() > 2 * 1024 * 1024) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String content) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.staged');
    try {
      await staged.writeAsString(content, flush: true);
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }
}
