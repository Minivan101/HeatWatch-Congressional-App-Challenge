import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';

Map<String, dynamic> weatherFixture() => jsonDecode(
  File('test/fixtures/weather/open_meteo_recorded.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> alertFixture() => {
  'type': 'FeatureCollection',
  'updated': '2026-10-02T18:00:00Z',
  'features': [
    {
      'type': 'Feature',
      'id': 'https://api.weather.gov/alerts/urn:oid:fictional-test',
      'properties': {
        'id': 'urn:oid:fictional-test',
        'event': 'Heat Advisory',
        'headline': 'Fictional test only: heat advisory',
        'description': 'Exact test text.\nSecond line – preserve punctuation.',
        'instruction': 'Fictional instructions, not a real warning.',
        'senderName': 'Fictional NWS test office',
        'severity': 'Moderate',
        'status': 'Test',
        'messageType': 'Update',
        'sent': '2026-10-02T10:00:00-07:00',
        'effective': '2026-10-02T10:00:00-07:00',
        'onset': '2026-10-02T11:00:00-07:00',
        'expires': '2026-10-02T20:00:00-07:00',
        'ends': null,
        'references': [
          {'identifier': 'fictional-original-id'},
        ],
        'areaDesc': 'Fictional test area',
      },
    },
  ],
};

void main() {
  test(
    'weather request covers the route date picker and overnight arrival',
    () {
      final query = OpenMeteoProvider.requestFor(WeatherPlace.savedArea)
          .queryParameters;
      expect(query['past_days'], '1');
      expect(query['forecast_days'], '9');
      expect(query['timeformat'], 'unixtime');
      expect(query['hourly'], contains('uv_index'));
    },
  );
  const place = WeatherPlace.savedArea;
  final now = DateTime.fromMillisecondsSinceEpoch(
    (weatherFixture()['current']['time'] as int) * 1000,
    isUtc: true,
  ).add(const Duration(minutes: 5));
  WeatherReading parse(Map<String, dynamic> d) =>
      OpenMeteoProvider.parse(d, place: place, fetchedAt: now);

  test('compact request stays on the free endpoint with no key', () {
    final uri = OpenMeteoProvider.requestFor(place);
    expect(uri.host, 'api.open-meteo.com');
    expect(uri.scheme, 'https');
    expect(
      uri.queryParameters['hourly'],
      'uv_index,temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,precipitation_probability',
    );
    expect(
      uri.queryParameters['daily'],
      'uv_index_max,temperature_2m_max,temperature_2m_min,sunrise,sunset',
    );
    expect(uri.queryParameters['timeformat'], 'unixtime');
    expect(uri.queryParameters.containsKey('apikey'), false);
    expect(
      NwsAlertProvider.requestFor(place).queryParameters['point'],
      '36.19531,-115.28587',
    );
  });

  test(
    'recorded weather uses Celsius and absolute forecast hour intervals',
    () {
      final d = weatherFixture();
      final reading = parse(d);
      expect(reading.temperatureC, d['current']['temperature_2m']);
      expect(reading.feelsLikeC, d['current']['apparent_temperature']);
      expect(reading.humidityPercent, d['current']['relative_humidity_2m']);
      expect(reading.currentValidAt!.isUtc, true);
      final sample = reading.hourlyUv[10];
      expect(
        reading.uvFor(sample.validAt.add(const Duration(minutes: 59))),
        sample,
      );
      expect(
        reading.uvFor(sample.validAt.add(const Duration(hours: 1))),
        reading.hourlyUv[11],
      );
      expect(
        reading.uvFor(sample.validAt.subtract(const Duration(days: 3))),
        null,
      );
      expect(reading.dailyUv.first.localDate, '2026-10-02');
      expect(reading.currentFreshAt(now), true);
      expect(reading.currentFreshAt(now.add(const Duration(hours: 1))), false);
      expect(reading.forecastFreshAt(now.add(const Duration(hours: 1))), false);
    },
  );

  test('missing UV is unknown, while actual numeric zero stays zero', () {
    final d = weatherFixture();
    d['hourly']['uv_index'][0] = null;
    d['hourly']['uv_index'][1] = 0;
    final reading = parse(d);
    expect(reading.hourlyUv[0].value, null);
    expect(reading.hourlyUv[1].value, 0);
    expect(reading.temperatureC, isNotNull);
    expect(
      reading.issues,
      contains('Some hourly UV values unavailable or invalid.'),
    );
  });

  test('weather, hourly UV and daily maximum can be missing independently', () {
    final d = weatherFixture()..remove('current');
    final reading = parse(d);
    expect(reading.temperatureC, null);
    expect(reading.hourlyUv, isNotEmpty);
    final noUv = weatherFixture()
      ..remove('hourly')
      ..remove('daily');
    expect(parse(noUv).temperatureC, isNotNull);
    expect(parse(noUv).hourlyUv, isEmpty);
    expect(parse(noUv).dailyUv, isEmpty);
  });

  test(
    'unit mismatch and invalid humidity do not contaminate valid fields',
    () {
      final d = weatherFixture();
      d['current_units']['temperature_2m'] = '°F';
      d['current']['relative_humidity_2m'] = 101;
      final reading = parse(d);
      expect(reading.temperatureC, null);
      expect(reading.humidityPercent, null);
      expect(reading.feelsLikeC, isNotNull);
      expect(reading.hourlyUv, isNotEmpty);
    },
  );

  test('bad UV alignment is rejected, never matched to the wrong hour', () {
    final d = weatherFixture();
    d['hourly']['time'][1] = d['hourly']['time'][0];
    expect(parse(d).hourlyUv, isEmpty);
    expect(parse(d).temperatureC, isNotNull);
    final mismatch = weatherFixture();
    (mismatch['hourly']['uv_index'] as List).removeLast();
    expect(parse(mismatch).hourlyUv.every((s) => s.value == null), true);
  });

  test(
    'future current time is not usable; unrelated grid and bad point reject',
    () {
      final d = weatherFixture();
      d['current']['time'] =
          now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
      expect(parse(d).temperatureC, null);
      expect(
        () => parse(weatherFixture()..['latitude'] = 0),
        throwsFormatException,
      );
      expect(
        () => OpenMeteoProvider.requestFor(
          const WeatherPlace(
            label: 'Invalid',
            coordinates: Coordinates(latitude: 91, longitude: 0),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'NWS preserves IDs, wording, status, references, times and official link',
    () {
      final d = alertFixture();
      final reading = NwsAlertProvider.parse(d, place: place, fetchedAt: now);
      final record = reading.alerts.single;
      final p = (d['features'] as List).single['properties'];
      expect(record.id, p['id']);
      expect(record.headline, p['headline']);
      expect(record.description, p['description']);
      expect(record.instruction, p['instruction']);
      expect(record.raw, (d['features'] as List).single);
      expect(record.severity, 'Moderate');
      expect(record.status, 'Test');
      expect(record.messageType, 'Update');
      expect(record.effective, DateTime.utc(2026, 10, 2, 17));
      expect(record.onset, DateTime.utc(2026, 10, 2, 18));
      expect(record.expires, DateTime.utc(2026, 10, 3, 3));
      expect(record.ends, null);
      expect(record.sourceUrl.host, 'api.weather.gov');
    },
  );

  test('empty valid collection differs from incomplete or malformed NWS', () {
    final d = jsonDecode(
      File('test/fixtures/weather/nws_recorded.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      NwsAlertProvider.parse(d, place: place, fetchedAt: now).alerts,
      isEmpty,
    );
    for (final bad in [
      {'type': 'FeatureCollection'},
      {
        ...d,
        'pagination': {'next': 'https://api.weather.gov/next'},
      },
    ]) {
      expect(
        () => NwsAlertProvider.parse(bad, place: place, fetchedAt: now),
        throwsFormatException,
      );
    }
    final bad = alertFixture();
    bad['features'][0]['properties']['effective'] = '2026-10-02T12:00:00';
    expect(
      () => NwsAlertProvider.parse(bad, place: place, fetchedAt: now),
      throwsFormatException,
    );
    final unsafe = alertFixture();
    unsafe['features'][0]['id'] = 'https://example.com/wrong';
    expect(
      () => NwsAlertProvider.parse(unsafe, place: place, fetchedAt: now),
      throwsFormatException,
    );
  });

  test('free HTTP sends NWS identification and parses UTF-8 exactly', () async {
    final transport = FreeWeatherHttp(
      client: MockClient((request) async {
        expect(request.followRedirects, false);
        expect(request.headers['User-Agent'], contains('HeatWatch'));
        expect(request.headers['Accept'], 'application/geo+json');
        return http.Response(
          jsonEncode(alertFixture()),
          200,
          headers: {'content-type': 'application/geo+json; charset=utf-8'},
        );
      }),
    );
    final reading = await NwsAlertProvider(
      transport: transport,
      clock: () => now,
    ).fetch(place);
    expect(reading.alerts.single.description, contains('–'));
  });

  test(
    'weather survives failed alerts without claiming a successful check',
    () async {
      final transport = FreeWeatherHttp(
        client: MockClient((request) async {
          return request.url.host == 'api.open-meteo.com'
              ? http.Response(
                  jsonEncode(weatherFixture()),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                )
              : http.Response('temporarily unavailable', 503);
        }),
      );
      final result = await FreeWeatherService(
        weather: OpenMeteoProvider(transport: transport, clock: () => now),
        alerts: NwsAlertProvider(transport: transport, clock: () => now),
      ).fetch(place);
      expect(result.weather, isNotNull);
      expect(result.alerts, null);
      expect(result.alertError, 'Official alerts could not be checked.');
    },
  );

  test(
    'alerts survive weather failure with no fictional weather fallback',
    () async {
      final transport = FreeWeatherHttp(
        client: MockClient(
          (request) async => request.url.host == 'api.weather.gov'
              ? http.Response('{"type":"FeatureCollection","features":[]}', 200)
              : http.Response('blocked', 403),
        ),
      );
      final result = await FreeWeatherService(
        weather: OpenMeteoProvider(transport: transport, clock: () => now),
        alerts: NwsAlertProvider(transport: transport, clock: () => now),
      ).fetch(place);
      expect(result.weather, null);
      expect(result.alerts!.alerts, isEmpty);
      expect(result.weatherError, 'Weather could not be checked.');
    },
  );

  test(
    'HTTP rejects unsafe endpoints, redirects and excessive bodies',
    () async {
      final transport = FreeWeatherHttp(
        client: MockClient((_) async => http.Response('', 302)),
      );
      await expectLater(
        transport.get(Uri.parse('http://api.open-meteo.com/')),
        throwsFormatException,
      );
      await expectLater(
        transport.get(Uri.parse('https://customer-api.open-meteo.com/')),
        throwsFormatException,
      );
      await expectLater(
        transport.get(OpenMeteoProvider.requestFor(place)),
        throwsStateError,
      );
      final oversized = FreeWeatherHttp(
        client: MockClient(
          (_) async => http.Response('a' * (FreeWeatherHttp.maxBytes + 1), 200),
        ),
      );
      await expectLater(
        oversized.get(OpenMeteoProvider.requestFor(place)),
        throwsFormatException,
      );
    },
  );
}
