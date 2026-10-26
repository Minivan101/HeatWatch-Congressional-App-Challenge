import 'cooling_cache_store.dart';

class CoolingCache implements CoolingCacheStore {
  String? _content;
  @override
  Future<String?> read() async => _content;
  @override
  Future<void> write(String content) async => _content = content;
}
