import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';

void main() {
  final uri = Uri.parse(
    'https://api.weather.gov/alerts/active?point=36.19,-115.28',
  );
  test(
    'temporary NWS HTTP failure gets one delayed retry then succeeds',
    () async {
      var calls = 0;
      final delays = <Duration>[];
      final client = MockClient(
        (_) async => ++calls == 1
            ? http.Response('busy', 503)
            : http.Response('{"features":[]}', 200),
      );
      final response = await FreeWeatherHttp(
        client: client,
        wait: (d) async => delays.add(d),
      ).getResponse(uri, nws: true);
      expect(calls, 2);
      expect(delays, [const Duration(seconds: 5)]);
      expect(response.data['features'], isEmpty);
      client.close();
    },
  );
  test('persistent NWS failure stops after two attempts', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('busy', 503);
    });
    await expectLater(
      FreeWeatherHttp(
        client: client,
        wait: (_) async {},
      ).getResponse(uri, nws: true),
      throwsA(isA<WeatherHttpFailure>()),
    );
    expect(calls, 2);
    client.close();
  });
  test(
    'long Retry-After, permanent HTTP error and malformed data do not retry',
    () async {
      for (final response in [
        http.Response('busy', 429, headers: {'retry-after': '120'}),
        http.Response('denied', 403),
        http.Response('bad json', 200),
      ]) {
        var calls = 0, delays = 0;
        final client = MockClient((_) async {
          calls++;
          return response;
        });
        await expectLater(
          FreeWeatherHttp(
            client: client,
            wait: (_) async {
              delays++;
            },
          ).getResponse(uri, nws: true),
          throwsA(anything),
        );
        expect(calls, 1);
        expect(delays, 0);
        client.close();
      }
    },
  );
  test('Open-Meteo failure retains existing repository retry policy', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('busy', 503);
    });
    await expectLater(
      FreeWeatherHttp(
        client: client,
        wait: (_) async {},
      ).getResponse(Uri.parse('https://api.open-meteo.com/v1/forecast')),
      throwsA(isA<WeatherHttpFailure>()),
    );
    expect(calls, 1);
    client.close();
  });
}
