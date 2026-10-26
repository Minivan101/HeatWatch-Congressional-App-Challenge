abstract class CoolingCacheStore {
  Future<String?> read();
  Future<void> write(String content);
}
