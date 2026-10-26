import 'uv_level_badge.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/data_status.dart';

import '../../../core/models/coordinates.dart';
import '../../cool_spots/models/cooling_destination.dart';
import '../models/free_weather.dart';
import '../services/weather_repository.dart';
import '../services/alert_lifecycle.dart';
import 'weather_guidance.dart';
import 'trip_summary_content.dart';

class RouteWeatherPanel extends StatefulWidget {
  const RouteWeatherPanel({
    super.key,
    required this.destination,
    required this.repository,
    this.origin,
    this.active = true,
    this.autoCheck = false,
    this.clock = DateTime.now,
    this.routeDuration,
    this.onClearDestination,
    this.plannedDeparture,
    this.shadeDescription,
    this.heading = 'Your trip',
  });
  final CoolingDestination destination;
  final Coordinates? origin;
  final WeatherRepository repository;
  final bool active, autoCheck;
  final DateTime Function() clock;
  final Duration? routeDuration;
  final VoidCallback? onClearDestination;
  final DateTime? plannedDeparture;
  final String? shadeDescription;
  final String heading;
  @override
  State<RouteWeatherPanel> createState() => _RouteWeatherPanelState();
}

class _RouteWeatherPanelState extends State<RouteWeatherPanel>
    with WidgetsBindingObserver {
  FreeWeatherResult? _start;
  FreeWeatherResult? _end;
  bool _busy = false;
  bool _checkFailed = false;
  bool _started = false;
  bool _resumed = true;
  int _minutes = 30;
  int _hours = 0;
  int _token = 0;
  DateTime? _departure;
  Timer? _timer;
  WeatherPlace get _origin => widget.origin == null
      ? WeatherPlace.savedArea
      : WeatherPlace(
          label: 'Selected route start',
          coordinates: widget.origin!,
        );
  WeatherPlace get _destination => WeatherPlace(
    label: widget.destination.name,
    coordinates: widget.destination.location,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _start != null) setState(() {});
      if (mounted && _started && widget.active && _resumed && !_busy) _check();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && widget.active && _started && !_busy) _check();
  }

  @override
  void didUpdateWidget(RouteWeatherPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination.id != widget.destination.id ||
        oldWidget.destination.name != widget.destination.name ||
        oldWidget.destination.location.latitude !=
            widget.destination.location.latitude ||
        oldWidget.destination.location.longitude !=
            widget.destination.location.longitude ||
        oldWidget.origin?.latitude != widget.origin?.latitude ||
        oldWidget.origin?.longitude != widget.origin?.longitude) {
      _token++;
      _start = null;
      _end = null;
      _started = false;
      _busy = false;
      _checkFailed = false;
      _restore();
    } else if (!oldWidget.active && widget.active && _started && !_busy) {
      _check();
    }
    if (widget.autoCheck && widget.active && !_started && !_busy) {
      unawaited(_check(manual: true));
    }
  }

  Future<void> _restore() async {
    final token = _token;
    var failed = false;
    Future<FreeWeatherResult?> restore(WeatherPlace place) async {
      try {
        return await widget.repository.cachedFor(place);
      } catch (_) {
        failed = true;
        return null;
      }
    }

    final results = await Future.wait([
      restore(_origin),
      restore(_destination),
    ]);
    if (!mounted || token != _token) return;
    setState(() {
      _start = results[0];
      _end = results[1];
      _checkFailed = failed;
      _departure ??= widget.clock().toUtc().add(Duration(hours: _hours));
    });
    if (widget.autoCheck && widget.active && !_started && !_busy) {
      await _check(manual: true);
    }
  }

  Future<void> _check({bool manual = false}) async {
    if (manual) _started = true;
    final token = ++_token;
    setState(() {
      _busy = true;
      _checkFailed = false;
      if (_hours == 0 || _departure == null) {
        _departure = widget.clock().toUtc().add(Duration(hours: _hours));
      }
    });
    try {
      final results = await Future.wait([
        widget.repository.refresh(_origin),
        widget.repository.refresh(_destination),
      ]);
      if (!mounted || token != _token) return;
      setState(() {
        _start = results[0];
        _end = results[1];
        _busy = false;
      });
    } catch (_) {
      if (mounted && token == _token) {
        setState(() {
          _busy = false;
          _checkFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.routeDuration ?? Duration(minutes: _minutes);
    final departure =
        widget.plannedDeparture?.toUtc() ??
        (_hours == 0
            ? widget.clock().toUtc()
            : (_departure ??
                  widget.clock().toUtc().add(Duration(hours: _hours))));
    final arrival = departure.add(duration);
    String time(DateTime at) {
      final local = at.toLocal();
      return '${local.month}/${local.day} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.heading, style: Theme.of(context).textTheme.titleLarge),
            const Text('Destination'),
            Text(
              widget.destination.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.origin == null
                  ? 'From: saved map area (planning point)'
                  : 'From: selected location',
            ),
            Text('Depart ${time(departure)} · arrive ${time(arrival)}'),
            if (_hours > 0 && departure.isBefore(widget.clock().toUtc()))
              const Text('Departure has passed — change your plan.'),
            Text(
              widget.routeDuration == null
                  ? '$_minutes min planned — not a calculated ETA'
                  : '${(duration.inSeconds / 60).ceil()} min route estimate',
            ),
            const SizedBox(height: 12),
            TripSummaryContent(
              start: _start,
              end: _end,
              departure: departure,
              arrival: arrival,
              now: widget.clock(),
              shadeDescription: widget.shadeDescription,
            ),
            if (widget.plannedDeparture == null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Change departure and walking time'),
                children: [
                  if (widget.routeDuration == null) ...[
                    const Text('Planned walking time — your assumption:'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final minutes in [15, 30, 60])
                          ChoiceChip(
                            label: Text('$minutes min'),
                            selected: _minutes == minutes,
                            onSelected: (_) =>
                                setState(() => _minutes = minutes),
                          ),
                      ],
                    ),
                  ],
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final hours in [0, 1, 2, 4])
                        ChoiceChip(
                          label: Text(
                            hours == 0 ? 'Leave now' : 'Leave in $hours h',
                          ),
                          selected: _hours == hours,
                          onSelected: (_) => setState(() {
                            _hours = hours;
                            _departure = widget.clock().toUtc().add(
                              Duration(hours: hours),
                            );
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            const Text(
              'Checking shares the start and destination with Open-Meteo and NWS.',
            ),
            FilledButton(
              onPressed: _busy ? null : () => _check(manual: true),
              child: const Text('Check departure & arrival weather'),
            ),
            if (_busy ||
                _checkFailed ||
                [_start, _end].any(
                  (r) =>
                      r?.weatherError != null ||
                      r?.alertError != null ||
                      r?.weatherFromCache == true ||
                      r?.alertsFromCache == true,
                ))
              DataStatus(
                loading: _busy,
                failed:
                    _checkFailed ||
                    [_start, _end].any(
                      (r) => r?.weatherError != null || r?.alertError != null,
                    ),
                saved: true,
                message: _busy
                    ? 'Checking departure and arrival…'
                    : _checkFailed ||
                          [_start, _end].any(
                            (r) =>
                                r?.weatherError != null ||
                                r?.alertError != null,
                          )
                    ? 'Trip update incomplete · retry available'
                    : 'Saved trip readings — check retrieval age in the report.',
                onRetry: () => _check(manual: true),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Trip details and sources'),
              children: [
                Text(widget.destination.address),
                SourceLink(
                  label: 'Destination source',
                  url: widget.destination.sourceUrl,
                ),
                const SourceLink(
                  label: 'Open-Meteo data and attribution',
                  url: 'https://open-meteo.com/',
                ),

                Text(
                  'Start: ${_origin.label} · End: ${widget.destination.name}',
                ),
                if (_start != null)
                  _Forecast(
                    title: 'Departure forecast',
                    at: departure,
                    result: _start!,
                    now: widget.clock(),
                  ),
                if (_end != null)
                  _Forecast(
                    title: 'Arrival forecast',
                    at: arrival,
                    result: _end!,
                    now: widget.clock(),
                  ),
              ],
            ),
            if (widget.onClearDestination != null)
              TextButton(
                onPressed: widget.onClearDestination,
                child: const Text('Clear destination'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Forecast extends StatelessWidget {
  const _Forecast({
    required this.title,
    required this.at,
    required this.result,
    required this.now,
  });
  final String title;
  final DateTime at;
  final FreeWeatherResult result;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final reading = result.weather;
    final conditions = reading?.conditionsFor(at);
    final uv = reading?.uvFor(at);
    final warnings = result.alerts == null
        ? <NwsAlert>[]
        : activeAlerts(result.alerts!, now.toUtc());
    final local = at.toLocal();
    String number(double? value) => value?.toStringAsFixed(1) ?? 'unavailable';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · ${local.month}/${local.day} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))} (device local time)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Modeled ${SettingsScope.temperature(context, conditions?.temperatureC)} · feels like ${SettingsScope.temperature(context, conditions?.feelsLikeC)} · UV ${number(uv?.value)}',
          ),
          UvLevelBadge(showValue: false, value: uv?.value),
          if (reading == null) const Text('Forecast unavailable.'),
          if (reading != null && result.weatherFromCache)
            const Text('Saved forecast; see retrieval age below.'),
          if (result.cacheNotice != null) Text(result.cacheNotice!),
          if (reading != null &&
              (!reading.forecastFreshAt(now) || result.weatherError != null))
            const Text('Saved forecast · refresh available.'),
          if (reading != null)
            Text(
              'Open-Meteo · retrieved ${now.toUtc().difference(reading.fetchedAt).inMinutes.clamp(0, 999999)} min ago',
            ),
          if (result.alertError != null)
            const Text(
              'Official warnings could not be refreshed for this point.',
            ),
          if (result.alerts != null && warnings.isEmpty)
            Text(
              result.alertError != null ||
                      result.alertsFromCache ||
                      !result.alerts!.freshAt(now.toUtc())
                  ? 'Saved alert check'
                  : 'No currently effective warnings returned for this point.',
            ),
          for (final warning in warnings) ...[
            Text('Official warning: ${warning.headline ?? warning.event}'),
            if (warning.description != null)
              SelectableText(warning.description!),
            if (warning.instruction != null)
              SelectableText(warning.instruction!),
            if (result.alertsFromCache || !result.alerts!.freshAt(now.toUtc()))
              const Text('Saved warning; current status needs a fresh check.'),
            SourceLink(
              label: 'Read official warning',
              url: warning.sourceUrl.toString(),
            ),
          ],
        ],
      ),
    );
  }
}
