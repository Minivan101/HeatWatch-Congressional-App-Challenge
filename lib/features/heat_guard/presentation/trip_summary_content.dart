import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';

import '../models/free_weather.dart';
import '../services/alert_lifecycle.dart';
import 'uv_level_badge.dart';

class TripSummaryContent extends StatelessWidget {
  const TripSummaryContent({
    super.key,
    required this.start,
    required this.end,
    required this.departure,
    required this.arrival,
    required this.now,
    this.shadeDescription,
  });
  final FreeWeatherResult? start, end;
  final DateTime departure, arrival, now;
  final String? shadeDescription;

  @override
  Widget build(BuildContext context) {
    final warnings = <String, NwsAlert>{};
    for (final result in [start, end]) {
      if (result?.alerts case final reading?) {
        for (final alert in activeAlerts(reading, now.toUtc())) {
          final old = warnings[alert.id];
          if (old == null || alert.sent.isAfter(old.sent)) {
            warnings[alert.id] = alert;
          }
        }
      }
    }
    const severity = {
      'Extreme': 4,
      'Severe': 3,
      'Moderate': 2,
      'Minor': 1,
      'Unknown': 0,
    };
    final ordered = warnings.values.toList()
      ..sort(
        (a, b) =>
            (severity[b.severity] ?? 0).compareTo(severity[a.severity] ?? 0),
      );
    bool freshAlerts(FreeWeatherResult? r) =>
        r?.alerts != null &&
        r!.alertError == null &&
        !r.alertsFromCache &&
        r.alerts!.freshAt(now.toUtc());
    final complete = freshAlerts(start) && freshAlerts(end);
    final alertText = ordered.isNotEmpty
        ? '${ordered.first.event}${ordered.length > 1 ? ' · ${ordered.length} alerts' : ''}'
        : complete
        ? 'No currently effective alerts returned at either point'
        : 'Alerts not checked';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ordered.isNotEmpty
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Official alerts now'),
              Text(alertText, style: Theme.of(context).textTheme.titleSmall),
              if (ordered.isNotEmpty && !complete)
                const Text('Saved alert check'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Conditions(
          label: 'Departure weather',
          result: start,
          at: departure,
          now: now,
        ),
        _Conditions(
          label: 'Arrival weather',
          result: end,
          at: arrival,
          now: now,
        ),
        const SizedBox(height: 8),
        Text(shadeDescription ?? 'Building shade: not calculated'),
      ],
    );
  }
}

class _Conditions extends StatelessWidget {
  const _Conditions({
    required this.label,
    required this.result,
    required this.at,
    required this.now,
  });
  final String label;
  final FreeWeatherResult? result;
  final DateTime at, now;
  @override
  Widget build(BuildContext context) {
    final reading = result?.weather;
    final conditions = reading?.conditionsFor(at);
    final uv = reading?.uvFor(at)?.value;
    String value(double? number, [String unit = '']) =>
        number == null ? 'unknown' : '${number.toStringAsFixed(1)}$unit';
    final stale =
        reading != null &&
        (!reading.forecastFreshAt(now.toUtc()) || result!.weatherError != null);
    final status = stale
        ? 'Outdated / refresh failed'
        : result?.weatherFromCache == true
        ? 'Saved forecast'
        : 'Modeled forecast';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          Text(
            '${SettingsScope.temperature(context, conditions?.temperatureC, missing: 'unknown')} · feels ${SettingsScope.temperature(context, conditions?.feelsLikeC, missing: 'unknown')} · UV ${value(uv)}',
          ),
          UvLevelBadge(showValue: false, value: uv),
          Text(
            reading == null ? 'Not checked or unavailable' : status,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
