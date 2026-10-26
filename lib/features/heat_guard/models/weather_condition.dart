enum WeatherSky {
  unknown,
  clear,
  mainlyClear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  rain,
  snow,
  thunderstorm,
}

class WeatherCondition {
  const WeatherCondition(this.sky, this.label, {this.isDay});
  final WeatherSky sky;
  final String label;
  final bool? isDay;

  static const codes = {
    0,
    1,
    2,
    3,
    45,
    48,
    51,
    53,
    55,
    56,
    57,
    61,
    63,
    65,
    66,
    67,
    71,
    73,
    75,
    77,
    80,
    81,
    82,
    85,
    86,
    95,
    96,
    97,
    99,
  };

  factory WeatherCondition.fromCode(int? code, {bool? isDay}) {
    final (sky, label) = switch (code) {
      0 => (WeatherSky.clear, 'Clear'),
      1 => (WeatherSky.mainlyClear, 'Mostly clear'),
      2 => (WeatherSky.partlyCloudy, 'Partly cloudy'),
      3 => (WeatherSky.overcast, 'Overcast'),
      45 || 48 => (WeatherSky.fog, 'Fog'),
      51 || 53 || 55 => (WeatherSky.drizzle, 'Drizzle'),
      56 || 57 => (WeatherSky.drizzle, 'Freezing drizzle'),
      61 || 63 || 65 => (WeatherSky.rain, 'Rain'),
      66 || 67 => (WeatherSky.rain, 'Freezing rain'),
      80 || 81 || 82 => (WeatherSky.rain, 'Rain showers'),
      71 || 73 || 75 || 77 => (WeatherSky.snow, 'Snow'),
      85 || 86 => (WeatherSky.snow, 'Snow showers'),
      95 || 97 => (WeatherSky.thunderstorm, 'Thunderstorm'),
      96 || 99 => (WeatherSky.thunderstorm, 'Thunderstorm · hail'),
      _ => (WeatherSky.unknown, 'Weather'),
    };
    return WeatherCondition(sky, label, isDay: isDay);
  }
}
