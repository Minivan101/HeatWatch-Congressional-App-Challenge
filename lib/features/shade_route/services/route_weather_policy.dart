import '../../heat_guard/models/free_weather.dart';
import '../../heat_guard/models/weather_condition.dart';

WeatherCondition? routeConditionAt(
  WeatherReading? reading,
  DateTime departure,
  DateTime now,
) {
  if (reading == null) return null;
  final nearNow =
      departure.difference(now).abs() <= const Duration(minutes: 15);
  return nearNow && reading.currentFreshAt(now) ? reading.condition : null;
}

bool cloudsMakeShadeComparisonIrrelevant(WeatherCondition? condition) =>
    switch (condition?.sky) {
      WeatherSky.overcast ||
      WeatherSky.fog ||
      WeatherSky.drizzle ||
      WeatherSky.rain ||
      WeatherSky.snow ||
      WeatherSky.thunderstorm => true,
      _ => false,
    };
