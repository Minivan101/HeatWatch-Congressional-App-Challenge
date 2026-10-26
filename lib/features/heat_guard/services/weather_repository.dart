import 'dart:convert';
import 'dart:math' as math;

import '../../../core/models/coordinates.dart';
import '../models/free_weather.dart';
import 'free_weather_providers.dart';
import 'weather_cache.dart';
import 'weather_cache_store.dart';

class _PointState {
  WeatherReading? weather;
  AlertReading? alerts;
  DateTime? weatherDue;
  DateTime? alertsDue;
  int weatherFailures = 0;
  int alertFailures = 0;
  String? weatherError;
  String? alertError;
}

class WeatherRepository {
  WeatherRepository({
    this.weather = const OpenMeteoProvider(),
    this.alerts = const NwsAlertProvider(),
    WeatherCacheStore? cache,
    this.clock = DateTime.now,
  }) : cache = cache ?? WeatherCache();
  final WeatherProvider weather;
  final AlertProvider alerts;
  final WeatherCacheStore cache;
  final DateTime Function() clock;
  final _states = <String, _PointState>{};
  final _pending = <String, Future<FreeWeatherResult>>{};
  Future<void>? _restoring;
  Future<void> _writes = Future.value();
  String? _cacheNotice;
  int _generation = 0;
  static const weatherInterval = Duration(minutes: 15);
  static const alertInterval = Duration(minutes: 5);

  static String pointKey(WeatherPlace place) =>
      '${place.coordinates.latitude},${place.coordinates.longitude}';

  Future<FreeWeatherResult?> cachedFor(WeatherPlace place) async {
    place.validate();
    await (_restoring ??= _restore());
    final state = _states[pointKey(place)];
    if (state == null || (state.weather == null && state.alerts == null)) {
      return null;
    }
    return _result(place, state, true, true);
  }

  Future<void> _restore() async {
    try {
      final text = await cache.read();
      if (text == null) return;
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException('Cache version');
      final p = data['place'] as Map;
      final place = WeatherPlace(
        label: p['label'] as String,
        coordinates: Coordinates(
          latitude: (p['latitude'] as num).toDouble(),
          longitude: (p['longitude'] as num).toDouble(),
        ),
      );
      place.validate();
      final state = _PointState();
      try {
        if (data['weather'] != null) {
          final entry = data['weather'] as Map;
          final at = _cacheTime(entry['fetchedAt']);
          state.weather = OpenMeteoProvider.parse(
            Map<String, dynamic>.from(entry['raw'] as Map),
            place: place,
            fetchedAt: at,
            refreshAfter: _optionalTime(entry['refreshAfter']),
            sourceCheckedAt: entry['sourceCheckedAt'] == null
                ? null
                : _cacheTime(entry['sourceCheckedAt']),
          );
          state.weatherDue = _due(
            at,
            weatherInterval,
            state.weather!.refreshAfter,
          );
        }
      } catch (_) {
        _cacheNotice = 'Invalid saved weather was ignored.';
      }
      try {
        if (data['alerts'] != null) {
          final entry = data['alerts'] as Map;
          final at = _cacheTime(entry['fetchedAt']);
          state.alerts = NwsAlertProvider.parse(
            Map<String, dynamic>.from(entry['raw'] as Map),
            place: place,
            fetchedAt: at,
            refreshAfter: _optionalTime(entry['refreshAfter']),
            sourceCheckedAt: entry['sourceCheckedAt'] == null
                ? null
                : _cacheTime(entry['sourceCheckedAt']),
          );
          state.alertsDue = _due(at, alertInterval, state.alerts!.refreshAfter);
        }
      } catch (_) {
        _cacheNotice = 'Invalid saved alert data was ignored.';
      }
      _states[pointKey(place)] = state;
    } catch (_) {
      _cacheNotice = 'Saved readings unavailable; live checks still work.';
    }
  }

  DateTime _cacheTime(Object? value) {
    if (value is! String || !value.endsWith('Z')) {
      throw const FormatException('Cache time');
    }
    final at = DateTime.parse(value).toUtc();
    if (at.isAfter(clock().toUtc().add(const Duration(minutes: 5)))) {
      throw const FormatException('Future cache');
    }
    return at;
  }

  DateTime? _optionalTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
  DateTime _due(DateTime at, Duration interval, DateTime? providerUntil) {
    final next = at.add(interval);
    return providerUntil != null && providerUntil.isAfter(next)
        ? providerUntil
        : next;
  }

  Future<FreeWeatherResult> refresh(WeatherPlace place) {
    place.validate();
    final key = pointKey(place);
    final existing = _pending[key];
    if (existing != null) return existing;
    final future = _refresh(place);
    _pending[key] = future;
    return future.whenComplete(() {
      if (identical(_pending[key], future)) _pending.remove(key);
    });
  }

  Future<FreeWeatherResult> _refresh(WeatherPlace place) async {
    final generation = _generation;
    await (_restoring ??= _restore());
    final key = pointKey(place);
    final state = _states.putIfAbsent(key, _PointState.new);
    final now = clock().toUtc();
    var weatherCached = true;
    var alertsCached = true;
    var updated = false;
    bool due(DateTime? at) => at == null || !now.isBefore(at);
    await Future.wait([
      (() async {
        if (!due(state.weatherDue)) return;
        try {
          final value = await weather.fetch(place);
          if (generation != _generation) return;
          state.weather = value;
          state.weatherDue = _due(
            value.fetchedAt,
            weatherInterval,
            value.refreshAfter,
          );
          state.weatherFailures = 0;
          state.weatherError = null;
          weatherCached = false;
          updated = true;
        } catch (e) {
          if (generation != _generation) return;
          state.weatherDue = _retry(
            ++state.weatherFailures,
            clock().toUtc(),
            e,
          );
          state.weatherError =
              'Weather could not be refreshed. Retry after ${state.weatherDue!.toLocal()}.';
        }
      })(),
      (() async {
        if (!due(state.alertsDue)) return;
        try {
          final value = await alerts.fetch(place);
          if (generation != _generation) return;

          state.alerts = value;
          state.alertsDue = _due(
            value.fetchedAt,
            alertInterval,
            value.refreshAfter,
          );
          state.alertFailures = 0;
          state.alertError = null;
          alertsCached = false;
          updated = true;
        } catch (e) {
          if (generation != _generation) return;
          state.alertsDue = _retry(++state.alertFailures, clock().toUtc(), e);
          state.alertError =
              'Official alerts could not be refreshed. Retry after ${state.alertsDue!.toLocal()}.';
        }
      })(),
    ]);
    if (updated && generation == _generation) {
      final encoded = _encode(place, state);

      _writes = _writes.then((_) async {
        if (generation != _generation) return;
        try {
          if (encoded == null) {
            await cache.clear();
          } else {
            await cache.write(encoded);
          }
          _cacheNotice = null;
        } catch (_) {
          _cacheNotice = 'Readings loaded, but offline saving failed.';
        }
      });
      await _writes;
    }

    while (_states.length > 3) {
      final removable = _states.keys.where(
        (k) => k != key && !_pending.containsKey(k),
      );
      if (removable.isEmpty) break;
      _states.remove(removable.first);
    }
    return _result(place, state, weatherCached, alertsCached);
  }

  DateTime _retry(int failures, DateTime now, Object error) {
    final seconds = math
        .min(900, 30 * math.pow(2, math.min(failures - 1, 5)))
        .toInt();
    final backoff = now.add(Duration(seconds: seconds));
    final specified = error is WeatherHttpFailure ? error.retryAt : null;
    return specified != null && specified.isAfter(backoff)
        ? specified
        : backoff;
  }

  FreeWeatherResult _result(
    WeatherPlace place,
    _PointState state,
    bool w,
    bool a,
  ) => FreeWeatherResult(
    place: place,
    weather: state.weather,
    alerts: state.alerts,
    weatherError: state.weatherError,
    alertError: state.alertError,
    weatherFromCache: w && state.weather != null,
    alertsFromCache: a && state.alerts != null,
    cacheNotice: _cacheNotice,
  );

  String? _encode(WeatherPlace place, _PointState state) {
    if ((state.weather == null ||
            !state.weather!.mayPersist ||
            state.weather!.raw.isEmpty) &&
        (state.alerts == null || !state.alerts!.mayPersist)) {
      return null;
    }
    return jsonEncode({
      'version': 1,
      'place': {
        'label': place.label,
        'latitude': place.coordinates.latitude,
        'longitude': place.coordinates.longitude,
      },
      'weather':
          state.weather == null ||
              !state.weather!.mayPersist ||
              state.weather!.raw.isEmpty
          ? null
          : {
              'fetchedAt': state.weather!.fetchedAt.toUtc().toIso8601String(),
              'sourceCheckedAt': state.weather!.sourceCheckedAt
                  ?.toUtc()
                  .toIso8601String(),
              'refreshAfter': state.weather!.refreshAfter
                  ?.toUtc()
                  .toIso8601String(),
              'raw': state.weather!.raw,
            },
      'alerts': state.alerts == null || !state.alerts!.mayPersist
          ? null
          : {
              'fetchedAt': state.alerts!.fetchedAt.toUtc().toIso8601String(),
              'sourceCheckedAt': state.alerts!.sourceCheckedAt
                  ?.toUtc()
                  .toIso8601String(),
              'refreshAfter': state.alerts!.refreshAfter
                  ?.toUtc()
                  .toIso8601String(),
              'raw': {
                'type': 'FeatureCollection',
                'updated': state.alerts!.providerUpdatedAt
                    ?.toUtc()
                    .toIso8601String(),
                'features': state.alerts!.alerts.map((a) => a.raw).toList(),
              },
            },
    });
  }

  Future<void> clear() async {
    _generation++;
    await (_restoring ?? Future.value());
    _states.clear();
    _pending.clear();
    await _writes;
    await cache.clear();
    _cacheNotice = null;
  }
}
