abstract class WeatherCacheStore {
  Future<String?> read();
  Future<void> write(String content);
  Future<void> clear();
}
