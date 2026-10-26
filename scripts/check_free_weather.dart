import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/heat_guard/models/free_weather.dart';
import 'package:heatwatch/features/heat_guard/services/free_weather_providers.dart';

Future<void> main() async {
  final result = await const FreeWeatherService().fetch(WeatherPlace.savedArea);
  final now = DateTime.now().toUtc();
  final weather = result.weather;
  final uv = weather?.uvFor(now);
  final report = {
    'checkedAt': now.toIso8601String(),
    'place': result.place.label,
    'weatherReceived': weather != null,
    'currentValidAt': weather?.currentValidAt?.toIso8601String(),
    'temperatureC': weather?.temperatureC,
    'feelsLikeC': weather?.feelsLikeC,
    'humidityPercent': weather?.humidityPercent,
    'forecastUvAtCheckTime': uv?.value,
    'hourlyForecastTemperatureC': weather?.conditionsFor(now)?.temperatureC,
    'hourlyForecastFeelsLikeC': weather?.conditionsFor(now)?.feelsLikeC,
    'hourlyForecastHumidityPercent': weather
        ?.conditionsFor(now)
        ?.humidityPercent,
    'forecastUvHour': uv?.validAt.toIso8601String(),
    'forecastHours': weather?.hourlyUv.length,
    'uvHoursWithValues': weather?.hourlyUv.where((v) => v.value != null).length,
    'forecastStartsAt': weather == null || weather.hourlyUv.isEmpty
        ? null
        : weather.hourlyUv.first.validAt.toIso8601String(),
    'forecastEndsAt': weather == null || weather.hourlyUv.isEmpty
        ? null
        : weather.hourlyUv.last.validAt.toIso8601String(),
    'currentFresh': weather?.currentFreshAt(now),
    'weatherIssues': weather?.issues,
    'weatherError': result.weatherError,
    'nwsChecked': result.alerts != null,
    'nwsRecordsReturned': result.alerts?.alerts.length,
    'nwsError': result.alertError,
    'note': 'One free-service check for this point/time, not evidence of weather everywhere or future availability.',
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  if (result.weather == null || result.alerts == null) exitCode = 1;
}
