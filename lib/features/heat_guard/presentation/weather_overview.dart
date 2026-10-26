import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../models/free_weather.dart';
import '../models/weather_condition.dart';
import 'weather_visuals.dart' show weatherConditionIcon;

class WeatherOverview extends ChangeNotifier {
  WeatherPlace place = WeatherPlace.savedArea;
  FreeWeatherResult? result;
  bool busy = false, _disposed = false;
  VoidCallback? chooseLocation;
  void update(WeatherPlace selected, FreeWeatherResult? reading, bool loading) {
    if (_disposed) return;
    place = selected;
    result = reading;
    busy = loading;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class WeatherOverviewScope extends InheritedNotifier<WeatherOverview> {
  const WeatherOverviewScope({
    super.key,
    required WeatherOverview overview,
    required super.child,
  }) : super(notifier: overview);
  static WeatherOverview? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WeatherOverviewScope>()
      ?.notifier;
}

class CurrentTemperatureDisplay extends StatelessWidget {
  const CurrentTemperatureDisplay({
    super.key,
    this.onOpen,
    this.compact = false,
    this.clock = DateTime.now,
  });
  final VoidCallback? onOpen;
  final bool compact;
  final DateTime Function() clock;
  @override
  Widget build(BuildContext context) {
    final overview = WeatherOverviewScope.maybeOf(context);
    final reading = overview?.result?.weather;
    final now = clock().toUtc();
    final saved =
        reading != null &&
        (!reading.currentFreshAt(now) ||
            overview!.result!.weatherError != null);
    final settings = SettingsScope.maybeOf(context);
    final value = SettingsScope.temperature(
      context,
      reading?.temperatureC,
      missing: '—°${settings?.fahrenheit == true ? 'F' : 'C'}',
    );
    final condition =
        reading?.condition ??
        const WeatherCondition(WeatherSky.unknown, 'Weather');
    final status = saved
        ? 'Saved'
        : overview?.busy == true
        ? 'Updating'
        : condition.sky == WeatherSky.unknown
        ? 'Temperature'
        : condition.label;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            weatherConditionIcon(condition),
            key: const ValueKey('persistent-weather-icon'),
            semanticLabel: condition.sky == WeatherSky.unknown
                ? 'Weather condition unavailable'
                : condition.label,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF90CAF9)
                : const Color(0xFF1976D2),
            size: 24,
          ),
          const SizedBox(width: 3),
          if (compact)
            Text(
              value,
              key: const ValueKey('persistent-temperature'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  key: const ValueKey('persistent-temperature'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(status, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
    return Tooltip(
      message: '${overview?.place.label ?? 'Las Vegas'} · $status $value',
      child: onOpen == null
          ? content
          : InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(12),
              child: content,
            ),
    );
  }
}
