import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';
import 'package:heatwatch/features/heat_guard/services/alert_lifecycle.dart';
import 'package:heatwatch/features/heat_guard/services/weather_repository.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_memory.dart';
import 'package:heatwatch/features/heat_guard/services/weather_cache_file.dart'
    as native;

import 'free_weather_providers_test.dart' show weatherFixture, alertFixture;

class WeatherFake implements WeatherProvider {
  WeatherFake(this.load);
  final Future<WeatherReading> Function(WeatherPlace) load;
  int calls = 0;
  @override
  Future<WeatherReading> fetch(WeatherPlace place) {
    calls++;
    return load(place);
  }
}

class AlertsFake implements AlertProvider {
  AlertsFake(this.load);
  final Future<AlertReading> Function(WeatherPlace) load;
  int calls = 0;
  @override
  Future<AlertReading> fetch(WeatherPlace place) {
    calls++;
    return load(place);
  }
}

WeatherReading readingAt(
  WeatherPlace place,
  DateTime at, {
  bool persist = true,
  DateTime? due,
}) {
  final d = weatherFixture();
  d['latitude'] = place.coordinates.latitude;
  d['longitude'] = place.coordinates.longitude;
  d['current']['time'] = at.millisecondsSinceEpoch ~/ 1000;
  d['current']['temperature_2m'] = 35;
  d['hourly_units']['temperature_2m'] = '°C';
  d['hourly_units']['apparent_temperature'] = '°C';
  d['hourly_units']['relative_humidity_2m'] = '%';
  final n = (d['hourly']['time'] as List).length;
  d['hourly']['temperature_2m'] = List.filled(n, 35);
  d['hourly']['apparent_temperature'] = List.filled(n, 36);
  d['hourly']['relative_humidity_2m'] = List.filled(n, 20);
  return OpenMeteoProvider.parse(
    d,
    place: place,
    fetchedAt: at,
    mayPersist: persist,
    refreshAfter: due,
  );
}

Map<String, dynamic> alertRecord(
  String id, {
  String type = 'Alert',
  List<String> refs = const [],
  String status = 'Actual',
  String severity = 'Severe',
  String expires = '2026-10-03T03:00:00Z',
}) {
  final d = (alertFixture()['features'] as List).single as Map<String, dynamic>;
  d['id'] = 'https://api.weather.gov/alerts/$id';
  final p = d['properties'] as Map;
  p['id'] = id;
  p['messageType'] = type;
  p['status'] = status;
  p['severity'] = severity;
  p['expires'] = expires;
  p['effective'] = '2026-10-02T17:00:00Z';
  p['references'] = refs.map((r) => {'identifier': r}).toList();
  return d;
}

AlertReading alertReading(
  WeatherPlace place,
  DateTime now,
  List<Object> features, {
  bool persist = true,
}) => NwsAlertProvider.parse(
  {'type': 'FeatureCollection', 'features': features},
  place: place,
  fetchedAt: now,
  mayPersist: persist,
);

void main() {
  const place = WeatherPlace.savedArea;
  final initial = DateTime.utc(2026, 10, 2, 18, 30);
  test(
    'duplicates, updates, cancellations, expiration and test records reconcile',
    () {
      final old = alertRecord('old');
      final replacement = alertRecord('new', type: 'Update', refs: ['old']);
      final snapshot = alertReading(place, initial, [
        old,
        old,
        replacement,
        alertRecord('expired', expires: '2026-10-02T18:00:00Z'),
        alertRecord('test', status: 'Test'),
      ]);
      expect(activeAlerts(snapshot, initial).map((a) => a.id), ['new']);
      final cancel = alertRecord(
        'cancel',
        type: 'Cancel',
        refs: ['new', 'old'],
      );
      expect(
        activeAlerts(
          alertReading(place, initial, [old, replacement, cancel]),
          initial,
        ),
        isEmpty,
      );
      expect(
        activeAlerts(snapshot, initial.add(const Duration(days: 2))),
        isEmpty,
      );
      expect(
        activeAlerts(
          alertReading(place, initial, [
            alertRecord('low', severity: 'Minor'),
            replacement,
          ]),
          initial,
        ).first.id,
        'new',
      );
    },
  );

  test(
    'simultaneous requests deduplicate and each provider has its own cadence',
    () async {
      var now = initial;
      final gate = Completer<void>();
      final w = WeatherFake((p) async {
        await gate.future;
        return readingAt(p, now);
      });
      final a = AlertsFake((p) async {
        await gate.future;
        return alertReading(p, now, []);
      });
      final repo = WeatherRepository(
        weather: w,
        alerts: a,
        cache: WeatherCache(),
        clock: () => now,
      );
      final first = repo.refresh(place);
      final second = repo.refresh(place);
      gate.complete();
      await Future.wait([first, second]);
      expect(w.calls, 1);
      expect(a.calls, 1);
      await repo.refresh(place);
      expect(w.calls, 1);
      expect(a.calls, 1);
      now = now.add(const Duration(minutes: 6));
      await repo.refresh(place);
      expect(w.calls, 1);
      expect(a.calls, 2);
      now = initial.add(const Duration(minutes: 16));
      await repo.refresh(place);
      expect(w.calls, 2);
      expect(a.calls, 3);
    },
  );

  test(
    'last successful values survive isolated failures, restart and offline use',
    () async {
      var now = initial;
      var fail = false;
      final dir = await Directory.systemTemp.createTemp(
        'heatwatch-weather-cache-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final cache = native.WeatherCache(directoryProvider: () async => dir);
      final w = WeatherFake((p) async {
        if (fail) throw StateError('offline');
        return readingAt(p, now);
      });
      final a = AlertsFake((p) async {
        if (fail) throw StateError('offline');
        return alertReading(p, now, [alertRecord('old')]);
      });
      final repo = WeatherRepository(
        weather: w,
        alerts: a,
        cache: cache,
        clock: () => now,
      );
      await repo.refresh(place);
      final original = await cache.read();
      fail = true;
      now = now.add(const Duration(minutes: 31));
      final failed = await repo.refresh(place);
      expect(failed.weather!.temperatureC, 35);
      expect(failed.alerts!.alerts.single.id, 'old');
      expect(failed.weatherError, isNotNull);
      expect(failed.alertError, isNotNull);
      expect(failed.weather!.currentFreshAt(now), false);
      expect(await cache.read(), original);
      final restarted = WeatherRepository(
        weather: w,
        alerts: a,
        cache: cache,
        clock: () => now,
      );
      final saved = await restarted.cachedFor(place);
      expect(saved!.weatherFromCache, true);
      expect(saved.alertsFromCache, true);
      expect(w.calls, 2);
      expect(a.calls, 2);
      await restarted.clear();
      expect(await cache.read(), null);
    },
  );

  test(
    'successful empty snapshot clears previous warnings; failed check does not',
    () async {
      var now = initial;
      var empty = false;
      var fail = false;
      final a = AlertsFake((p) async {
        if (fail) throw StateError('offline');
        return alertReading(p, now, empty ? [] : [alertRecord('old')]);
      });
      final repo = WeatherRepository(
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: a,
        cache: WeatherCache(),
        clock: () => now,
      );
      await repo.refresh(place);
      now = now.add(const Duration(minutes: 6));
      fail = true;
      expect((await repo.refresh(place)).alerts!.alerts, isNotEmpty);
      now = now.add(const Duration(minutes: 1));
      fail = false;
      empty = true;
      expect((await repo.refresh(place)).alerts!.alerts, isEmpty);
    },
  );

  test(
    'a slow failed alert request gets its full cooldown after completion',
    () async {
      var now = initial;
      final alerts = AlertsFake((p) async {
        now = now.add(const Duration(seconds: 45));
        throw WeatherHttpFailure(503);
      });
      final repo = WeatherRepository(
        weather: WeatherFake((p) async => readingAt(p, now)),
        alerts: alerts,
        cache: WeatherCache(),
        clock: () => now,
      );
      await repo.refresh(place);
      await repo.refresh(place);
      expect(alerts.calls, 1);
      now = now.add(const Duration(seconds: 29));
      await repo.refresh(place);
      expect(alerts.calls, 1);
      now = now.add(const Duration(seconds: 1));
      await repo.refresh(place);
      expect(alerts.calls, 2);
    },
  );

  test('backoff and Retry-After stop hammering; provider cache freshness defers refresh', () async {
    var now = initial;
    final w = WeatherFake(
      (p) async =>
          readingAt(p, now, due: initial.add(const Duration(hours: 1))),
    );
    final a = AlertsFake(
      (p) async => throw WeatherHttpFailure(
        429,
        retryAt: initial.add(const Duration(minutes: 10)),
      ),
    );
    final repo = WeatherRepository(
      weather: w,
      alerts: a,
      cache: WeatherCache(),
      clock: () => now,
    );
    await repo.refresh(place);
    now = initial.add(const Duration(minutes: 6));
    await repo.refresh(place);
    expect(w.calls, 1);
    expect(a.calls, 1);
    now = initial.add(const Duration(minutes: 11));
    await repo.refresh(place);
    expect(a.calls, 2);
    now = initial.add(const Duration(minutes: 61));
    await repo.refresh(place);
    expect(w.calls, 2);
  });

  test(
    'no-store payloads are not persisted and corrupt cache is ignored',
    () async {
      final cache = WeatherCache();
      await cache.write('not JSON');
      final repo = WeatherRepository(
        weather: WeatherFake(
          (p) async => readingAt(p, initial, persist: false),
        ),
        alerts: AlertsFake(
          (p) async => alertReading(p, initial, [], persist: false),
        ),
        cache: cache,
        clock: () => initial,
      );
      expect(await repo.cachedFor(place), null);
      expect((await repo.refresh(place)).weather, isNotNull);
      expect(await cache.read(), null);
    },
  );

  test('cache is scoped to exact coordinates, replaces one point, never stores history', () async {
    final cache = WeatherCache();
    final repo = WeatherRepository(
      weather: WeatherFake((p) async => readingAt(p, initial)),
      alerts: AlertsFake((p) async => alertReading(p, initial, [])),
      cache: cache,
      clock: () => initial,
    );
    await repo.refresh(place);
    const other = WeatherPlace(
      label: 'Other point',
      coordinates: Coordinates(latitude: 36.2, longitude: -115.2),
    );
    expect(await repo.cachedFor(other), null);
    await repo.refresh(other);
    final data = jsonDecode((await cache.read())!);
    expect(data['place']['latitude'], 36.2);
    expect(data.containsKey('history'), false);
    final restart = WeatherRepository(cache: cache, clock: () => initial);
    expect(await restart.cachedFor(place), null);
    expect(await restart.cachedFor(other), isNotNull);
  });

  test(
    'HTTP cache age, no-store and date Retry-After retain their meaning',
    () {
      final metadata = WeatherHttpResponse.fromHeaders({}, {
        'cache-control': 'public, max-age=1200',
        'age': '600',
      }, initial);
      expect(metadata.refreshAfter, initial.add(const Duration(minutes: 10)));
      expect(
        metadata.sourceCheckedAt,
        initial.subtract(const Duration(minutes: 10)),
      );
      expect(
        WeatherHttpResponse.fromHeaders({}, {
          'cache-control': 'no-store',
        }, initial).mayPersist,
        false,
      );
      expect(
        WeatherHttpResponse.fromHeaders({}, {
          'cache-control': 'no-cache, max-age=1200',
        }, initial).refreshAfter,
        null,
      );
      expect(
        retryTime('120', initial),
        initial.add(const Duration(minutes: 2)),
      );
      expect(
        retryTime('Fri, 02 Oct 2026 19:00:00 GMT', initial),
        DateTime.utc(2026, 10, 2, 19),
      );
    },
  );

  test('old HTTP response origin cannot become a fresh alert check', () {
    final snapshot = NwsAlertProvider.parse(
      {'type': 'FeatureCollection', 'features': []},
      place: place,
      fetchedAt: initial,
      sourceCheckedAt: initial.subtract(const Duration(minutes: 10)),
    );
    expect(snapshot.freshAt(initial), false);
  });

  test(
    'clear while a request is pending does not repopulate the saved file',
    () async {
      final gate = Completer<void>();
      final cache = WeatherCache();
      final repo = WeatherRepository(
        weather: WeatherFake((p) async {
          await gate.future;
          return readingAt(p, initial);
        }),
        alerts: AlertsFake((p) async {
          await gate.future;
          return alertReading(p, initial, []);
        }),
        cache: cache,
        clock: () => initial,
      );
      final pending = repo.refresh(place);
      await Future<void>.delayed(Duration.zero);
      await repo.clear();
      gate.complete();
      await pending;
      expect(await cache.read(), null);
      expect(await repo.cachedFor(place), null);
    },
  );

  test('missing UV leaves hourly temperature intact, future hours remain forecasts', () {
    final d = readingAt(place, initial).raw;
    final modified = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
    modified['hourly'].remove('uv_index');
    final reading = OpenMeteoProvider.parse(
      modified,
      place: place,
      fetchedAt: initial,
    );
    expect(reading.conditionsFor(initial)!.temperatureC, 35);
    expect(reading.uvFor(initial)!.value, null);
  });
}
