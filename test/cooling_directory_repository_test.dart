import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_cache_file.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_cache_store.dart';
import 'package:heatwatch/features/cool_spots/services/cooling_directory_repository.dart';

class MemoryCache implements CoolingCacheStore {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String content) async {
    if (fail) throw const FileSystemException('No storage');
    value = content;
  }
}

String bundle() =>
    File('data/cooling_centers/official_directory.json').readAsStringSync();
String revision(int revision) {
  final data = jsonDecode(bundle()) as Map<String, dynamic>;
  data['revision'] = revision;
  return jsonEncode(data);
}

void main() {
  test(
    'page loading stays offline; corrupt cache falls back to all 45 sites',
    () async {
      var calls = 0;
      final repository = CoolingDirectoryRepository(
        cache: MemoryCache()..value = '{}',
        client: MockClient((request) async {
          calls++;
          return http.Response('', 500);
        }),
        bundleLoader: () async => bundle(),
        feedUrl: 'https://example.test/official.json',
      );
      final snapshot = await repository.load();
      expect(calls, 0);
      expect(snapshot.directory.stations.length, 45);
      expect(snapshot.origin, 'Bundled offline copy');
    },
  );

  test(
    'valid newer HTTPS update persists and survives offline app restart',
    () async {
      final cache = MemoryCache();
      final repository = CoolingDirectoryRepository(
        cache: cache,
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          expect(request.url.query, isEmpty);
          return http.Response(
            revision(5),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        bundleLoader: () async => bundle(),
        feedUrl: 'https://example.test/official.json',
      );
      await repository.load();
      expect((await repository.refresh()).directory.revision, 5);
      final restarted = CoolingDirectoryRepository(
        cache: cache,
        bundleLoader: () async => bundle(),
      );
      expect((await restarted.load()).directory.revision, 5);
      expect((await restarted.refresh()).directory.revision, 5);
    },
  );

  for (final failure in [
    'malformed',
    'older',
    'same-revision-change',
    'http',
    'network',
    'storage',
    'oversize',
    'redirect',
  ]) {
    test('$failure retains the last valid directory and cache', () async {
      final cache = MemoryCache()..value = revision(5);
      if (failure == 'storage') cache.fail = true;
      var calls = 0;
      final repository = CoolingDirectoryRepository(
        cache: cache,
        bundleLoader: () async => bundle(),
        feedUrl:
            '${failure == 'http' ? 'http' : 'https'}://example.test/official.json',
        client: MockClient((request) async {
          calls++;
          switch (failure) {
            case 'network':
              throw const SocketException('Offline');
            case 'malformed':
              return http.Response('{}', 200);
            case 'older':
              return http.Response(revision(1), 200);
            case 'same-revision-change':
              final data = jsonDecode(revision(5));
              data['stations'][0]['name'] = 'Changed without revision';
              return http.Response(jsonEncode(data), 200);
            case 'oversize':
              return http.Response('x' * (2 * 1024 * 1024 + 1), 200);
            case 'redirect':
              return http.Response(
                '',
                302,
                headers: {'location': 'http://example.test'},
              );
            default:
              return http.Response(
                revision(6),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
          }
        }),
      );
      await repository.load();
      final before = cache.value;
      final snapshot = await repository.refresh();
      expect(snapshot.directory.revision, 5);
      expect(cache.value, before);
      expect(snapshot.notice, isNotNull);
      if (failure == 'http') expect(calls, 0);
    });
  }

  test('native file cache round-trips and staging file is removed', () async {
    final folder = Directory.systemTemp.createTempSync('cooling-cache-');
    try {
      final cache = CoolingCache(directoryProvider: () async => folder);
      expect(await cache.read(), isNull);
      await cache.write(revision(5));
      expect(jsonDecode((await cache.read())!)['revision'], 5);
      expect(
        folder.listSync().where((file) => file.path.endsWith('.staged')),
        isEmpty,
      );
    } finally {
      folder.deleteSync(recursive: true);
    }
  });
}
