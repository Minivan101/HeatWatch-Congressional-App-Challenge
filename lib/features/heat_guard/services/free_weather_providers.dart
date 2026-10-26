import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/models/coordinates.dart';
import '../models/free_weather.dart';
import '../models/weather_condition.dart';

abstract class WeatherProvider {
  Future<WeatherReading> fetch(WeatherPlace place);
}

abstract class AlertProvider {
  Future<AlertReading> fetch(WeatherPlace place);
}

class WeatherHttpFailure extends StateError {
  WeatherHttpFailure(this.statusCode, {this.retryAt})
    : super('Provider HTTP $statusCode');
  final int statusCode;
  final DateTime? retryAt;
}

DateTime? retryTime(String? value, DateTime now) {
  if (value == null) return null;
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) {
    return now.add(Duration(seconds: seconds));
  }

  return httpDate(value);
}

DateTime? httpDate(String value) {
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (m == null) return null;
  final month =
      [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ].indexOf(m[2]!) +
      1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
}

class WeatherHttpResponse {
  const WeatherHttpResponse(
    this.data,
    this.refreshAfter,
    this.mayPersist,
    this.sourceCheckedAt,
  );
  final Map<String, dynamic> data;
  final DateTime? refreshAfter;
  final bool mayPersist;
  final DateTime? sourceCheckedAt;
  factory WeatherHttpResponse.fromHeaders(
    Map<String, dynamic> data,
    Map<String, String> headers,
    DateTime now,
  ) {
    final control = (headers['cache-control'] ?? '').toLowerCase();
    final match = RegExp(r'(?:^|,)\s*max-age\s*=\s*"?(\d+)')
        .firstMatch(control);
    final age = int.tryParse(headers['age'] ?? '') ?? 0;
    final date = httpDate(headers['date'] ?? '');
    final apparentAge = date == null || date.isAfter(now)
        ? 0
        : now.difference(date).inSeconds;
    final usedAge = age > apparentAge ? age : apparentAge;
    DateTime? until;
    if (!control.contains('no-cache') && match != null) {
      final remaining = int.parse(match[1]!) - usedAge;
      until = now.add(Duration(seconds: remaining > 0 ? remaining : 0));
    } else if (!control.contains('no-cache')) {
      until = httpDate(headers['expires'] ?? '');
    }
    return WeatherHttpResponse(
      data,
      until,
      !control.contains('no-store'),
      usedAge > 0 ? now.subtract(Duration(seconds: usedAge)) : null,
    );
  }
}

Future<void> _weatherRetryWait(Duration delay) => Future<void>.delayed(delay);

class FreeWeatherHttp {
  const FreeWeatherHttp({this.client, this.wait = _weatherRetryWait});
  final http.Client? client;
  final Future<void> Function(Duration) wait;
  static const maxBytes = 2 * 1024 * 1024;

  Future<Map<String, dynamic>> get(Uri uri, {bool nws = false}) async =>
      (await getResponse(uri, nws: nws)).data;

  Future<WeatherHttpResponse> getResponse(Uri uri, {bool nws = false}) async {
    try {
      return await _getResponseOnce(uri, nws: nws);
    } catch (error) {
      if (!nws) rethrow;
      final now = DateTime.now().toUtc();
      if (error is WeatherHttpFailure) {
        if (![429, 502, 503, 504].contains(error.statusCode) ||
            error.retryAt != null &&
                error.retryAt!.isAfter(now.add(const Duration(seconds: 5)))) {
          rethrow;
        }
      } else if (error is! http.ClientException && error is! TimeoutException) {
        rethrow;
      }
      await wait(const Duration(seconds: 5));
      return _getResponseOnce(uri, nws: nws);
    }
  }

  Future<WeatherHttpResponse> _getResponseOnce(
    Uri uri, {
    bool nws = false,
  }) async {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !['api.open-meteo.com', 'api.weather.gov'].contains(uri.host)) {
      throw const FormatException('Unsupported free weather endpoint');
    }
    final transport = client ?? http.Client();
    try {
      return await (() async {
        final request = http.Request('GET', uri)..followRedirects = false;
        request.headers['Accept'] = nws
            ? 'application/geo+json'
            : 'application/json';
        if (nws) {
          request.headers['User-Agent'] = 'HeatWatch-Student-Prototype/0.1';
        }
        final response = await transport.send(request);
        if (response.statusCode != 200) {
          throw WeatherHttpFailure(
            response.statusCode,
            retryAt: retryTime(
              response.headers['retry-after'],
              DateTime.now().toUtc(),
            ),
          );
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw const FormatException('Weather response is too large');
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('Weather response is too large');
          }
          bytes.addAll(chunk);
        }
        return WeatherHttpResponse.fromHeaders(
          _map(jsonDecode(utf8.decode(bytes))),
          response.headers,
          DateTime.now().toUtc(),
        );
      })().timeout(const Duration(seconds: 20));
    } finally {
      if (client == null) transport.close();
    }
  }
}

// weather
class OpenMeteoProvider implements WeatherProvider {
  const OpenMeteoProvider({
    this.transport = const FreeWeatherHttp(),
    this.clock = DateTime.now,
  });
  final FreeWeatherHttp transport;
  final DateTime Function() clock;

  static Uri requestFor(WeatherPlace place) {
    place.validate();
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': place.coordinates.latitude.toString(),
      'longitude': place.coordinates.longitude.toString(),
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m',
      'hourly': 'uv_index,temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,precipitation_probability',
      'daily':
          'uv_index_max,temperature_2m_max,temperature_2m_min,sunrise,sunset',
      'wind_speed_unit': 'kmh',
      'temperature_unit': 'celsius',
      'timeformat': 'unixtime',
      'timezone': 'auto',

      'past_days': '1',
      'forecast_days': '9',
    });
  }

  @override
  Future<WeatherReading> fetch(WeatherPlace place) async {
    final response = await transport.getResponse(requestFor(place));
    return parse(
      response.data,
      place: place,
      fetchedAt: clock().toUtc(),
      refreshAfter: response.refreshAfter,
      mayPersist: response.mayPersist,
      sourceCheckedAt: response.sourceCheckedAt,
    );
  }

  static WeatherReading parse(
    Map<String, dynamic> data, {
    required WeatherPlace place,
    required DateTime fetchedAt,
    DateTime? refreshAfter,
    bool mayPersist = true,
    DateTime? sourceCheckedAt,
  }) {
    place.validate();
    final lat = _number(data['latitude']);
    final lon = _number(data['longitude']);
    if (lat == null ||
        lon == null ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        (lat - place.coordinates.latitude).abs() > 1 ||
        (lon - place.coordinates.longitude).abs() > 1) {
      throw const FormatException('Missing or unrelated weather grid point');
    }
    final zone = _string(data['timezone']);
    final offset = data['utc_offset_seconds'];
    if (offset is! int || offset.abs() > 86400) {
      throw const FormatException('Invalid weather timezone offset');
    }
    final issues = <String>[];
    final current = _optionalMap(data['current']);
    final units = _optionalMap(data['current_units']);
    final currentTime = _epoch(current['time']);
    final usableTime =
        units['time'] == 'unixtime' &&
        currentTime != null &&
        !currentTime.isAfter(fetchedAt.add(const Duration(minutes: 5)));
    if (!usableTime) issues.add('Current valid time unavailable or invalid.');
    double? field(String name, String unit, double min, double max) {
      final value = _number(current[name]);
      if (!usableTime ||
          units[name] != unit ||
          value == null ||
          value < min ||
          value > max) {
        issues.add('$name unavailable or invalid.');
        return null;
      }
      return value;
    }

    final temperature = field('temperature_2m', '°C', -100, 70);
    final apparent = field('apparent_temperature', '°C', -120, 100);
    final humidity = field('relative_humidity_2m', '%', 0, 100);
    final hourly = _optionalMap(data['hourly']);
    final hourlyUnits = _optionalMap(data['hourly_units']);
    final rawCode = _number(current['weather_code']);
    final weatherCode =
        usableTime &&
            units['weather_code'] == 'wmo code' &&
            rawCode != null &&
            rawCode == rawCode.roundToDouble() &&
            WeatherCondition.codes.contains(rawCode.toInt())
        ? rawCode.toInt()
        : null;
    final rawDay = _number(current['is_day']);
    final isDay =
        usableTime && units['is_day'] == '' && (rawDay == 0 || rawDay == 1)
        ? rawDay == 1
        : null;
    if (weatherCode == null) issues.add('Weather condition unavailable.');
    if (isDay == null) issues.add('Day/night indicator unavailable.');
    final samples = <TimedUv>[];
    final times = hourly['time'];
    final values = hourly['uv_index'];
    if (times is List && hourlyUnits['time'] == 'unixtime') {
      DateTime? previous;
      for (var i = 0; i < times.length; i++) {
        final at = _epoch(times[i]);
        if (at == null ||
            (previous != null &&
                at.difference(previous) != const Duration(hours: 1))) {
          samples.clear();
          issues.add('Hourly UV times invalid.');
          break;
        }
        previous = at;
        samples.add(
          TimedUv(
            at,
            values is List &&
                    values.length == times.length &&
                    hourlyUnits['uv_index'] == ''
                ? _uv(values[i])
                : null,
          ),
        );
      }
    }
    if (samples.isEmpty) issues.add('Hourly UV unavailable.');
    if (samples.any((s) => s.value == null)) {
      issues.add('Some hourly UV values unavailable or invalid.');
    }
    final conditions = <TimedConditions>[];
    double? forecastField(
      String name,
      String unit,
      int i,
      double min,
      double max,
    ) {
      final series = hourly[name];
      if (series is! List ||
          series.length != samples.length ||
          hourlyUnits[name] != unit) {
        return null;
      }
      final value = _number(series[i]);
      return value != null && value >= min && value <= max ? value : null;
    }

    for (var i = 0; i < samples.length; i++) {
      conditions.add(
        TimedConditions(
          samples[i].validAt,
          forecastField('temperature_2m', '°C', i, -100, 70),
          forecastField('apparent_temperature', '°C', i, -120, 100),
          forecastField('relative_humidity_2m', '%', i, 0, 100),
          weatherCode: () {
            final code = forecastField('weather_code', 'wmo code', i, 0, 99);
            return code != null &&
                    code == code.roundToDouble() &&
                    WeatherCondition.codes.contains(code.toInt())
                ? code.toInt()
                : null;
          }(),
          rainProbability: forecastField(
            'precipitation_probability',
            '%',
            i,
            0,
            100,
          ),
        ),
      );
    }
    final daily = _optionalMap(data['daily']);
    final dailyUnits = _optionalMap(data['daily_units']);
    final maxima = <DailyUv>[];
    final days = daily['time'];
    final dailyValues = daily['uv_index_max'];
    if (days is List &&
        dailyValues is List &&
        days.length == dailyValues.length &&
        dailyUnits['time'] == 'unixtime' &&
        dailyUnits['uv_index_max'] == '') {
      for (var i = 0; i < days.length; i++) {
        final at = _epoch(days[i]);
        if (at == null) {
          maxima.clear();
          issues.add('Daily UV dates invalid.');
          break;
        }

        final local = at.add(Duration(seconds: offset));
        maxima.add(
          DailyUv(
            local.toIso8601String().substring(0, 10),
            _uv(dailyValues[i]),
          ),
        );
      }
    }
    if (maxima.isEmpty) issues.add('Daily UV maximum unavailable.');
    final dailyConditions = <DailyConditions>[];
    if (days is List && dailyUnits['time'] == 'unixtime') {
      double? dailyField(String name, String unit, int i) {
        final values = daily[name];
        final v =
            values is List &&
                values.length == days.length &&
                dailyUnits[name] == unit
            ? _number(values[i])
            : null;
        return v != null && v >= -100 && v <= 70 ? v : null;
      }

      DateTime? solarField(String name, int i) {
        final values = daily[name];
        return values is List &&
                values.length == days.length &&
                dailyUnits[name] == 'unixtime'
            ? _epoch(values[i])
            : null;
      }

      for (var i = 0; i < days.length; i++) {
        final date = _epoch(days[i]);
        if (date == null) continue;
        final high = dailyField('temperature_2m_max', '°C', i);
        final low = dailyField('temperature_2m_min', '°C', i);
        final rise = solarField('sunrise', i), set = solarField('sunset', i);
        dailyConditions.add(
          DailyConditions(
            date
                .add(Duration(seconds: offset))
                .toIso8601String()
                .substring(0, 10),
            highC: high != null && (low == null || high >= low) ? high : null,
            lowC: low != null && (high == null || high >= low) ? low : null,
            sunrise: rise != null && set != null && rise.isBefore(set)
                ? rise
                : null,
            sunset: rise != null && set != null && rise.isBefore(set)
                ? set
                : null,
          ),
        );
      }
    }
    return WeatherReading(
      place: place,
      gridPoint: Coordinates(latitude: lat, longitude: lon),
      fetchedAt: fetchedAt.toUtc(),
      currentValidAt: usableTime ? currentTime : null,
      weatherCode: weatherCode,
      isDay: isDay,
      temperatureC: temperature,
      feelsLikeC: apparent,
      humidityPercent: humidity,
      hourlyUv: List.unmodifiable(samples),
      dailyUv: List.unmodifiable(maxima),
      timezone: zone,
      utcOffsetSeconds: offset,
      issues: List.unmodifiable(issues),
      hourlyConditions: List.unmodifiable(conditions),
      dailyConditions: List.unmodifiable(dailyConditions),
      windKmh: field('wind_speed_10m', 'km/h', 0, 500),
      raw: Map.unmodifiable(data),
      refreshAfter: refreshAfter,
      mayPersist: mayPersist,
      sourceCheckedAt: sourceCheckedAt,
    );
  }
}

// weather alerts
class NwsAlertProvider implements AlertProvider {
  const NwsAlertProvider({
    this.transport = const FreeWeatherHttp(),
    this.clock = DateTime.now,
  });
  final FreeWeatherHttp transport;
  final DateTime Function() clock;

  static Uri requestFor(WeatherPlace place) {
    place.validate();
    return Uri.https('api.weather.gov', '/alerts/active', {
      'point': '${place.coordinates.latitude},${place.coordinates.longitude}',
    });
  }

  @override
  Future<AlertReading> fetch(WeatherPlace place) async {
    final response = await transport.getResponse(requestFor(place), nws: true);
    return parse(
      response.data,
      place: place,
      fetchedAt: clock().toUtc(),
      refreshAfter: response.refreshAfter,
      mayPersist: response.mayPersist,
      sourceCheckedAt: response.sourceCheckedAt,
    );
  }

  static AlertReading parse(
    Map<String, dynamic> data, {
    required WeatherPlace place,
    required DateTime fetchedAt,
    DateTime? refreshAfter,
    bool mayPersist = true,
    DateTime? sourceCheckedAt,
  }) {
    place.validate();
    final features = data['features'];
    if (data['type'] != 'FeatureCollection' ||
        features is! List ||
        _optionalMap(data['pagination'])['next'] != null) {
      throw const FormatException('Incomplete NWS alert response');
    }
    final alerts = <NwsAlert>[];
    for (final value in features) {
      final feature = _map(value);
      if (feature['type'] != 'Feature') {
        throw const FormatException('Invalid NWS feature');
      }
      final p = _map(feature['properties']);
      final link = Uri.tryParse(_string(feature['id']));
      if (link == null ||
          link.scheme != 'https' ||
          link.host != 'api.weather.gov' ||
          !link.path.startsWith('/alerts/') ||
          link.userInfo.isNotEmpty) {
        throw const FormatException('Invalid official NWS source link');
      }
      final severity = _string(p['severity']);
      if (![
        'Unknown',
        'Minor',
        'Moderate',
        'Severe',
        'Extreme',
      ].contains(severity)) {
        throw const FormatException('Unknown NWS severity');
      }
      final status = _string(p['status']);
      final messageType = _string(p['messageType']);
      if (!['Actual', 'Exercise', 'System', 'Test', 'Draft'].contains(status) ||
          ![
            'Alert',
            'Update',
            'Cancel',
            'Ack',
            'Error',
          ].contains(messageType)) {
        throw const FormatException('Invalid NWS message status');
      }
      alerts.add(
        NwsAlert(
          id: _string(p['id']),
          sourceUrl: link,
          event: _string(p['event']),
          headline: _optionalString(p['headline']),
          description: _optionalString(p['description']),
          instruction: _optionalString(p['instruction']),
          senderName: _string(p['senderName']),
          severity: severity,
          status: status,
          messageType: messageType,
          sent: _instant(p['sent']),
          effective: _instant(p['effective']),
          onset: p['onset'] == null ? null : _instant(p['onset']),
          expires: _instant(p['expires']),
          ends: p['ends'] == null ? null : _instant(p['ends']),
          raw: Map.unmodifiable(feature),
        ),
      );
    }
    return AlertReading(
      place: place,
      fetchedAt: fetchedAt.toUtc(),
      providerUpdatedAt: data['updated'] == null
          ? null
          : _instant(data['updated']),
      alerts: List.unmodifiable(alerts),
      refreshAfter: refreshAfter,
      mayPersist: mayPersist,
      sourceCheckedAt: sourceCheckedAt,
    );
  }
}

class FreeWeatherService {
  const FreeWeatherService({
    this.weather = const OpenMeteoProvider(),
    this.alerts = const NwsAlertProvider(),
  });
  final WeatherProvider weather;
  final AlertProvider alerts;

  Future<FreeWeatherResult> fetch(WeatherPlace place) async {
    place.validate();
    WeatherReading? reading;
    AlertReading? warnings;
    String? weatherError;
    String? alertError;

    await Future.wait([
      (() async {
        try {
          reading = await weather.fetch(place);
        } catch (_) {
          weatherError = 'Weather could not be checked.';
        }
      })(),
      (() async {
        try {
          warnings = await alerts.fetch(place);
        } catch (_) {
          alertError = 'Official alerts could not be checked.';
        }
      })(),
    ]);
    return FreeWeatherResult(
      place: place,
      weather: reading,
      alerts: warnings,
      weatherError: weatherError,
      alertError: alertError,
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected provider object');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _optionalMap(Object? value) =>
    value == null ? <String, dynamic>{} : _map(value);
double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
double? _uv(Object? value) {
  final number = _number(value);
  return number != null && number >= 0 && number <= 100 ? number : null;
}

DateTime? _epoch(Object? value) {
  if (value is! int || value < 0 || value > 4102444800) return null;
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing provider text');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null || value is String) return value as String?;
  throw const FormatException('Invalid optional provider text');
}

DateTime _instant(Object? value) {
  final text = _string(value);
  if (!RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(text)) {
    throw const FormatException('Provider time lacks UTC offset');
  }
  final at = DateTime.tryParse(text);
  if (at == null) throw const FormatException('Invalid provider time');
  return at.toUtc();
}
