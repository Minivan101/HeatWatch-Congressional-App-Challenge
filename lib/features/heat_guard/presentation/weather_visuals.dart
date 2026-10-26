import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../models/weather_condition.dart';

import '../models/uv_level.dart';
import 'uv_level_badge.dart';

class CurrentWeatherCircle extends StatelessWidget {
  const CurrentWeatherCircle({super.key, required this.temperature});
  final String temperature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            key: const ValueKey('current-weather-circle'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer.withValues(alpha: .35),
              border: Border.all(
                color: scheme.primary.withValues(alpha: .35),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.thermostat_outlined,
                    color: scheme.primary,
                    size: 30,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        temperature,
                        key: const ValueKey('weather-current-temperature'),
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UvGauge extends StatelessWidget {
  const UvGauge({super.key, required this.value});
  final double? value;
  static const height = 200.0;

  static const scaleMax = 12.0;
  static const inset = 14.0;
  static const travel = height - inset * 2;

  @override
  Widget build(BuildContext context) {
    final level = UvLevel.fromValue(value);
    final (ink, _) = uvColors(level);
    final ratio = level == null ? null : value!.clamp(0.0, scaleMax) / scaleMax;
    return Semantics(
      label: 'UV index scale',
      value: level == null
          ? 'Unavailable'
          : '${value!.toStringAsFixed(1)}, ${level.label}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 90,
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: 8,
                top: inset,
                bottom: inset,
                width: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: level == null
                          ? [Colors.grey.shade400, Colors.grey.shade400]
                          : const [
                              Color(0xff388e3c),
                              Color(0xff388e3c),
                              Color(0xfffbc02d),
                              Color(0xfffbc02d),
                              Color(0xffef6c00),
                              Color(0xffef6c00),
                              Color(0xffd32f2f),
                              Color(0xffd32f2f),
                              Color(0xff7b1fa2),
                              Color(0xff7b1fa2),
                            ],
                      stops: level == null
                          ? null
                          : const [
                              0,
                              3 / scaleMax,
                              3 / scaleMax,
                              6 / scaleMax,
                              6 / scaleMax,
                              8 / scaleMax,
                              8 / scaleMax,
                              11 / scaleMax,
                              11 / scaleMax,
                              1,
                            ],
                    ),
                  ),
                ),
              ),
              for (final tick in [0, 3, 6, 8, 11])
                Positioned(
                  left: 44,
                  top: inset + travel * (1 - tick / scaleMax) - 10,
                  child: Text(
                    tick == 11 ? '11+' : '$tick',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w600),
                  ),
                ),
              if (ratio != null)
                AnimatedPositioned(
                  key: const ValueKey('uv-gauge-marker'),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  left: 3,
                  top: inset + travel * (1 - ratio) - 17,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ink,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeatherSection extends StatelessWidget {
  const WeatherSection({
    super.key,
    required this.child,
    this.borderColor,
    this.background,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final Color? borderColor, background;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: borderColor ?? Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    child: child,
  );
}

class WeatherMetricSections extends StatelessWidget {
  const WeatherMetricSections({
    super.key,
    required this.feelsLike,
    required this.humidity,
  });
  final String feelsLike, humidity;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget metric(String label, String value) => WeatherSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
      final feels = metric('Feels like', feelsLike),
          moisture = metric('Humidity', humidity);
      if (constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(16) > 24) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [feels, const SizedBox(height: 8), moisture],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: feels),
          const SizedBox(width: 8),
          Expanded(child: moisture),
        ],
      );
    },
  );
}

class WeatherSummaryHeader extends StatelessWidget {
  const WeatherSummaryHeader({
    super.key,
    required this.place,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    this.condition = const WeatherCondition(WeatherSky.unknown, 'Weather'),
  });
  final String place, temperature, feelsLike, humidity;
  final WeatherCondition condition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Heat Guard',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(place)),
          ],
        ),
      ],
    );
    final current = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(
          weatherConditionIcon(condition),
          key: const ValueKey('weather-condition-icon'),
          semanticLabel: condition.sky == WeatherSky.unknown
              ? 'Weather condition unavailable'
              : condition.label,
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF90CAF9)
              : const Color(0xFF1976D2),
          size: 48,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            temperature,
            key: const ValueKey('weather-current-temperature'),
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          condition.label,
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 240 ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [location, const SizedBox(height: 12), current],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: location),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: current),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('Feels like $feelsLike', style: theme.textTheme.bodySmall),
            Text('Humidity $humidity', style: theme.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

IconData weatherConditionIcon(WeatherCondition condition) =>
    switch (condition.sky) {
      WeatherSky.clear || WeatherSky.mainlyClear => switch (condition.isDay) {
        true => CupertinoIcons.sun_max_fill,
        false => CupertinoIcons.moon_stars_fill,
        null => Icons.brightness_6_outlined,
      },
      WeatherSky.partlyCloudy => switch (condition.isDay) {
        true => CupertinoIcons.cloud_sun_fill,
        false => CupertinoIcons.cloud_moon_fill,
        null => CupertinoIcons.cloud_fill,
      },
      WeatherSky.overcast => CupertinoIcons.cloud_fill,
      WeatherSky.fog => CupertinoIcons.cloud_fog_fill,
      WeatherSky.drizzle => CupertinoIcons.cloud_drizzle_fill,
      WeatherSky.rain => CupertinoIcons.cloud_rain_fill,
      WeatherSky.snow => CupertinoIcons.cloud_snow_fill,
      WeatherSky.thunderstorm => CupertinoIcons.cloud_bolt_rain_fill,
      WeatherSky.unknown => Icons.help_outline,
    };
