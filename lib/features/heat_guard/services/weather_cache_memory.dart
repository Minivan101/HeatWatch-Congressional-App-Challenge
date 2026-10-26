import 'weather_cache_store.dart';

class WeatherCache implements WeatherCacheStore {
  String? _content;
  @override
  Future<String?> read() async => _content;
  @override
  Future<void> write(String content) async => _content = content;
  @override
  Future<void> clear() async => _content = null;
}
