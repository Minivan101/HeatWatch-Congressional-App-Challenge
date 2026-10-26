import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/official_cooling_directory.dart';
import 'cooling_cache.dart';
import 'cooling_cache_store.dart';

class CoolingSnapshot {
  const CoolingSnapshot(this.directory, this.origin, {this.notice});
  final OfficialCoolingDirectory directory;
  final String origin;
  final String? notice;
}

class CoolingDirectoryRepository {
  CoolingDirectoryRepository({
    CoolingCacheStore? cache,
    this.client,
    this.bundleLoader = loadBundle,
    this.feedUrl = configuredFeed,
  }) : cache = cache ?? CoolingCache();

  static const configuredFeed = String.fromEnvironment('COOLING_DIRECTORY_URL');
  final CoolingCacheStore cache;
  final http.Client? client;
  final Future<String> Function() bundleLoader;
  final String feedUrl;
  CoolingSnapshot? _current;
  bool _refreshing = false;
  bool get hasFeed => feedUrl.isNotEmpty;

  static Future<String> loadBundle() =>
      rootBundle.loadString('data/cooling_centers/official_directory.json');

  Future<CoolingSnapshot> load() async {
    final bundled = OfficialCoolingDirectory.parse(
      jsonDecode(await bundleLoader()),
    );
    _current = CoolingSnapshot(bundled, 'Bundled offline copy');
    try {
      final text = await cache.read();
      if (text != null) {
        final cached = OfficialCoolingDirectory.parse(jsonDecode(text));
        if (cached.revision > bundled.revision) {
          _current = CoolingSnapshot(cached, 'Saved reviewed update');
        }
      }
    } catch (_) {
      _current = CoolingSnapshot(
        bundled,
        'Bundled offline copy',
        notice: 'Saved update unavailable. Using the bundled directory.',
      );
    }
    return _current!;
  }

  Future<CoolingSnapshot> refresh() async {
    final previous = _current ?? await load();
    if (!hasFeed) {
      return CoolingSnapshot(
        previous.directory,
        previous.origin,
        notice: 'Public updates are not configured. Saved locations remain available.',
      );
    }
    if (_refreshing) return previous;
    final uri = Uri.tryParse(feedUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return CoolingSnapshot(
        previous.directory,
        previous.origin,
        notice: 'Update URL must use HTTPS. Saved locations retained.',
      );
    }
    _refreshing = true;
    final connection = client ?? http.Client();
    try {
      final response = await connection
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const FormatException('Unavailable feed');
      }
      if ((response.contentLength ?? 0) > 2 * 1024 * 1024) {
        throw const FormatException('Oversized directory');
      }
      final bytes = <int>[];
      await (() async {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 10),
        )) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException('Oversized directory');
          }
          bytes.addAll(chunk);
        }
      })().timeout(const Duration(seconds: 15));
      final content = utf8.decode(bytes);
      final candidate = OfficialCoolingDirectory.parse(jsonDecode(content));
      if (candidate.revision < previous.directory.revision) {
        throw const FormatException('Older revision');
      }
      if (candidate.revision == previous.directory.revision) {
        if (jsonEncode(candidate.data) != jsonEncode(previous.directory.data)) {
          throw const FormatException('Changed data needs a new revision');
        }
        return CoolingSnapshot(
          previous.directory,
          previous.origin,
          notice: 'Already using the latest reviewed revision.',
        );
      }
      await cache.write(content);
      _current = CoolingSnapshot(
        candidate,
        'Downloaded reviewed update',
        notice: 'Directory updated. Opening status remains unverified.',
      );
      return _current!;
    } catch (_) {
      return CoolingSnapshot(
        previous.directory,
        previous.origin,
        notice: 'Update unavailable or rejected. Previous directory retained.',
      );
    } finally {
      if (client == null) connection.close();
      _refreshing = false;
    }
  }
}
