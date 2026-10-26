import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/location/app_location.dart';
import '../../../core/models/coordinates.dart';
import '../../shade_route/services/walking_navigation.dart';
import '../../../core/widgets/data_status.dart';

import 'package:flutter/services.dart';

import '../../../core/services/location_service.dart';
import '../../cool_spots/models/cooling_destination.dart';
import '../models/free_weather.dart';
import '../models/weather_condition.dart';
import '../services/free_weather_providers.dart';
import '../services/weather_repository.dart';
import '../services/alert_lifecycle.dart';
import 'weather_guidance.dart';
import 'weather_overview.dart';
import 'uv_level_badge.dart';
import 'weather_visuals.dart';
import 'home_dashboard.dart';
import 'weather_location_sheet.dart';
import '../models/uv_level.dart';

class FreeWeatherPreview extends StatefulWidget {
  const FreeWeatherPreview({
    super.key,
    this.service,
    this.repository,
    this.active = true,
    this.autoStart = false,
    this.keepOverviewUpdated = false,
    this.location = const LocationService(),
    this.destination,
    this.clock = DateTime.now,
    this.home = false,
    this.savedPlaces,
    this.onShade,
    this.onCool,
  });
  final FreeWeatherService? service;
  final WeatherRepository? repository;
  final bool active, autoStart, keepOverviewUpdated;
  final LocationService location;
  final CoolingDestination? destination;
  final DateTime Function() clock;
  final bool home;
  final VoidCallback? onShade, onCool;
  final Widget? savedPlaces;

  @override
  State<FreeWeatherPreview> createState() => _FreeWeatherPreviewState();
}

class _FreeWeatherPreviewState extends State<FreeWeatherPreview>
    with WidgetsBindingObserver {
  WeatherPlace _place = WeatherPlace.savedArea;
  FreeWeatherResult? _result;
  bool _busy = false;
  bool _locating = false;
  int _departureHours = 0;
  int _requestId = 0;
  DateTime? _departure;
  String? _locationError;
  Timer? _freshnessTimer;
  late final WeatherRepository _repository =
      widget.repository ?? WeatherRepository();
  bool _started = false;
  bool _autoRefresh = true;
  bool _resumed = true;

  WeatherOverview? _overview;
  int _publication = 0;
  bool get _viewed => widget.active || widget.keepOverviewUpdated;
  void _publishOverview() {
    if (!widget.keepOverviewUpdated) return;
    final version = ++_publication;
    final place = _place, result = _result, busy = _busy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && version == _publication) {
        _overview?.chooseLocation = _chooseLocation;
        _overview?.update(place, result, busy);
      }
    });
  }

  void _chooseLocation() =>
      showWeatherLocationSheet(context, onSelected: _select);

  double? _sharedLat, _sharedLon;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overview = WeatherOverviewScope.maybeOf(context);
    final shared = LocationScope.maybeOf(context);
    if (shared == null) return;
    final point = shared.position;
    if (_sharedLat == point?.latitude && _sharedLon == point?.longitude) return;

    if (shared.tracking &&
        point != null &&
        _sharedLat != null &&
        _sharedLon != null &&
        walkingDistance(
              Coordinates(latitude: _sharedLat!, longitude: _sharedLon!),
              point,
            ) <
            1000) {
      return;
    }
    _sharedLat = point?.latitude;
    _sharedLon = point?.longitude;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _select(
          point == null
              ? WeatherPlace.savedArea
              : WeatherPlace(label: 'Your location', coordinates: point),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _load(manual: true);
      });
    }

    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (_result != null) {
        setState(() {});
        _publishOverview();
      }
      if (_started &&
          _autoRefresh &&
          _viewed &&
          _resumed &&
          !_busy &&
          widget.service == null) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed &&
        _viewed &&
        _started &&
        _autoRefresh &&
        !_busy &&
        widget.service == null) {
      _load();
    }
  }

  Future<void> _restore() async {
    if (widget.service != null) return;
    final token = _requestId;
    final saved = await _repository.cachedFor(_place);
    if (!mounted || token != _requestId || saved == null) return;
    setState(() {
      _result = saved;
      _departure = widget.clock().toUtc().add(Duration(hours: _departureHours));
    });
    _publishOverview();
  }

  @override
  void didUpdateWidget(FreeWeatherPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_place.label == oldWidget.destination?.name &&
        (oldWidget.destination?.id != widget.destination?.id ||
            oldWidget.destination?.location.latitude !=
                widget.destination?.location.latitude ||
            oldWidget.destination?.location.longitude !=
                widget.destination?.location.longitude)) {
      _select(WeatherPlace.savedArea);
    }
    if (!oldWidget.active &&
        widget.active &&
        _started &&
        _autoRefresh &&
        !_busy &&
        widget.service == null) {
      _load();
    }
  }

  void _select(WeatherPlace place) {
    setState(() {
      _requestId++;
      _busy = false;
      _place = place;
      _result = null;
      _departure = null;
      _locationError = null;
      _started = false;
    });
    _publishOverview();
    _restore();
    if (widget.autoStart) _load(manual: true);
  }

  Future<void> _deviceLocation() async {
    final token = ++_requestId;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final point = await widget.location.getCurrentPosition();
      if (!mounted || token != _requestId) return;
      _select(WeatherPlace(label: 'Device location', coordinates: point));
    } on LocationAccessException catch (e) {
      if (mounted) setState(() => _locationError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationError = 'Location unavailable. Use the saved area.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _load({bool manual = false}) async {
    if (manual) _started = true;
    final token = ++_requestId;
    final selected = _place;
    final departure = widget.clock().toUtc().add(
      Duration(hours: _departureHours),
    );
    setState(() {
      _busy = true;
      _departure = departure;
    });
    _publishOverview();
    FreeWeatherResult result;
    try {
      result = widget.service != null
          ? await widget.service!.fetch(selected)
          : await _repository.refresh(selected);
    } catch (_) {
      result = FreeWeatherResult(
        place: selected,
        weather: null,
        alerts: null,
        weatherError: 'Weather could not be checked.',
        alertError: 'Official alerts could not be checked.',
      );
    }
    if (!mounted || token != _requestId) return;
    setState(() {
      _result = result;
      _busy = false;
    });
    _publishOverview();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.home) {
      return HomeDashboard(
        result: _result,
        place: _place,
        now: widget.clock().toUtc(),
        loading: _busy,
        onRefresh: () => _load(manual: true),
        onLocation: _chooseLocation,
        savedPlaces: widget.savedPlaces,
        onShade: widget.onShade,
        onCool: widget.onCool,
      );
    }
    final result = _result;
    final weather = result?.weather;
    final now = widget.clock().toUtc();
    final uvAt = _departureHours == 0 ? now : _departure;
    final uv = uvAt == null ? null : weather?.uvFor(uvAt);
    final level = UvLevel.fromValue(uv?.value);
    final (uvInk, uvBackground) = uvColors(level);
    final alerts = result?.alerts;
    final currentAlerts = alerts == null
        ? <NwsAlert>[]
        : activeAlerts(alerts, now);
    final savedWeather =
        weather != null &&
        (!weather.currentFreshAt(now) || result?.weatherError != null);
    final savedUv =
        weather != null &&
        (!weather.forecastFreshAt(now) || result?.weatherError != null);
    String age(DateTime at) =>
        '${now.difference(at).inMinutes.clamp(0, 999999)} min ago';
    final scheme = Theme.of(context).colorScheme;
    final futureConditions = _departure == null
        ? null
        : weather?.conditionsFor(_departure!);
    final alertCard = Card(
      key: const ValueKey('alert-summary'),
      color: currentAlerts.isEmpty ? null : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  currentAlerts.isEmpty
                      ? Icons.notifications_none
                      : Icons.warning_amber_rounded,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Official weather alerts',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (result == null)
              const Text('No live weather or official alert check yet.')
            else if (currentAlerts.isNotEmpty) ...[
              Text(
                currentAlerts.first.headline ?? currentAlerts.first.event,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'NWS · ${currentAlerts.first.severity} · ${currentAlerts.length} active alert${currentAlerts.length == 1 ? '' : 's'}',
              ),
              if (result.alertsFromCache ||
                  result.alertError != null ||
                  !alerts!.freshAt(now))
                const Text('Saved NWS alert'),
            ] else if (alerts == null)
              const Text('Official alerts could not be checked.')
            else if (!alerts.freshAt(now))
              const Text('Official alert check is outdated. Check again.')
            else
              Text(
                result.alertsFromCache || result.alertError != null
                    ? 'Saved alert check · refresh available'
                    : 'No active alerts returned by NWS for this point.',
              ),
            const Text('Local NWS warnings and instructions.'),
            ExpansionTile(
              key: const ValueKey('alert-details'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Alert details'),
              children: [
                if (alerts != null) ...[
                  Text('NWS checked: ${_local(context, alerts.fetchedAt)}'),
                  if (alerts.sourceCheckedAt != null)
                    Text(
                      'NWS HTTP response origin: ${_local(context, alerts.sourceCheckedAt!)}',
                    ),
                  if (alerts.providerUpdatedAt != null)
                    Text(
                      'NWS collection updated: ${_local(context, alerts.providerUpdatedAt!)}',
                    ),
                  for (final alert in currentAlerts)
                    _OfficialRecord(alert: alert),
                  if (alerts.alerts.length != currentAlerts.length)
                    ExpansionTile(
                      title: const Text('Other original NWS records'),
                      children: [
                        for (final original in alerts.alerts)
                          if (!currentAlerts.contains(original))
                            _OfficialRecord(alert: original),
                      ],
                    ),
                ],
                if (result?.alertError != null) Text(result!.alertError!),
              ],
            ),
          ],
        ),
      ),
    );
    final weatherDetails = WeatherSection(
      borderColor: scheme.outlineVariant,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ExpansionTile(
        key: const ValueKey('weather-details'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Weather details'),
        children: [
          if (weather != null) ...[
            if (weather.currentValidAt != null)
              Text(
                'Conditions time: ${_local(context, weather.currentValidAt!)}',
              ),
            Text('Retrieved ${_local(context, weather.fetchedAt)}'),
            Text(
              weather.timezone == 'America/Los_Angeles'
                  ? 'Forecast time zone: Pacific Time (ID: America/Los_Angeles)'
                  : 'Forecast time zone: ${weather.timezone}',
            ),
            if (weather.sourceCheckedAt != null)
              Text(
                'Weather HTTP response origin: ${_local(context, weather.sourceCheckedAt!)}',
              ),
            Text(
              'Forecast grid: ${weather.gridPoint.latitude.toStringAsFixed(5)}, ${weather.gridPoint.longitude.toStringAsFixed(5)}',
            ),
            if (weather.issues.isNotEmpty)
              ExpansionTile(
                title: const Text('Data notes'),
                children: [for (final issue in weather.issues) Text(issue)],
              ),
          ],
          Text(
            'Selected point: ${_place.coordinates.latitude.toStringAsFixed(5)}, ${_place.coordinates.longitude.toStringAsFixed(5)}',
          ),
          if (_departureHours > 0 && _departure != null) ...[
            Text('Departure: ${_local(context, _departure!)}'),
            Text(
              'Forecast ${SettingsScope.temperature(context, futureConditions?.temperatureC)} · feels ${SettingsScope.temperature(context, futureConditions?.feelsLikeC)}',
            ),
          ],
          if (result?.weatherError != null) Text(result!.weatherError!),
          if (result?.cacheNotice != null) Text(result!.cacheNotice!),
          const Text(
            'Open-Meteo forecasts, formatted by HeatWatch. Times use this device’s local time.',
          ),
          const SourceLink(
            label: 'Open-Meteo · CC BY 4.0',
            url: 'https://open-meteo.com/',
          ),
          const SourceLink(
            label: 'Forecast data license · CC BY 4.0',
            url: 'https://creativecommons.org/licenses/by/4.0/',
          ),
          const Text(
            'In hot weather, seek cooler places and stay hydrated. Follow official warnings.',
          ),
          const SourceLink(
            label: 'CDC heat guidance',
            url: 'https://www.cdc.gov/heat-health/about/index.html',
          ),
        ],
      ),
    );
    final uvDetails = WeatherSection(
      borderColor: uvInk.withValues(alpha: .35),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ExpansionTile(
        key: const ValueKey('uv-details'),
        tilePadding: EdgeInsets.zero,
        title: const Text('UV details'),
        children: [
          WeatherSection(
            background: uvBackground,
            borderColor: uvInk.withValues(alpha: .35),
            child: UvGauge(value: uv?.value),
          ),
          const SizedBox(height: 8),
          if (uv != null) Text('Forecast hour: ${_local(context, uv.validAt)}'),
          if (_departure != null && _departureHours > 0)
            Text('Departure: ${_local(context, _departure!)}'),
          if (weather != null)
            Text('Forecast retrieved: ${_local(context, weather.fetchedAt)}'),
          ExpansionTile(
            title: const Text('Daily UV outlook'),
            children: [
              for (final day in weather?.dailyUv ?? <DailyUv>[])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Daily maximum UV ${day.localDate}: ${day.maximum?.toStringAsFixed(1) ?? '—'}',
                      ),
                      UvLevelBadge(value: day.maximum, showValue: false),
                    ],
                  ),
                ),
            ],
          ),
          const Text(
            'UV levels: Low 0–2, Moderate 3–5, High 6–7, Very high 8–10, Extreme 11+.',
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final band in UvLevel.values)
                UvLevelBadge(level: band, showValue: false),
            ],
          ),
          const SourceLink(
            label: 'EPA UV scale',
            url: 'https://www.epa.gov/sunsafety/uv-index-scale-0',
          ),
          const Text(
            'UV and heat are different: low UV can still come with high temperatures.',
          ),
          const Text(
            'If you feel faint or weak in the heat, stop activity and move to a cool place.',
          ),
          const SourceLink(
            label: 'CDC sun protection',
            url: 'https://www.cdc.gov/skin-cancer/sun-safety/index.html',
          ),
          const SourceLink(
            label: 'CDC outdoor heat tips',
            url: 'https://www.cdc.gov/heat-health/risk-factors/heat-and-athletes.html',
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (currentAlerts.isNotEmpty) alertCard,
        Card(
          key: const ValueKey('weather-summary'),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF182B3C)
              : const Color(0xFFEFF7FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeatherSummaryHeader(
                  place: _place.label,
                  condition:
                      weather?.condition ??
                      const WeatherCondition(WeatherSky.unknown, 'Weather'),
                  temperature: SettingsScope.temperature(
                    context,
                    weather?.temperatureC,
                    missing: '—',
                  ),
                  feelsLike: SettingsScope.temperature(
                    context,
                    weather?.feelsLikeC,
                    missing: '—',
                  ),
                  humidity: weather?.humidityPercent == null
                      ? '—'
                      : '${weather!.humidityPercent!.toStringAsFixed(0)}%',
                ),
                if (weather != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${savedWeather ? 'Saved weather' : 'Updated'} · ${age(weather.fetchedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          key: const ValueKey('uv-summary'),
          color: uvBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: uvInk.withValues(alpha: .4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: uvInk),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'UV index',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: uvInk,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  level == null
                                      ? '—'
                                      : uv!.value!.toStringAsFixed(1),
                                  key: const ValueKey('uv-current-value'),
                                  style: const TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              level == null
                                  ? 'UV unavailable'
                                  : '${level.label} UV',
                              style: const TextStyle(fontSize: 20),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.wb_sunny_outlined, color: uvInk, size: 34),
                    ],
                  ),
                  const SizedBox(height: 8),
                  WeatherSection(
                    key: const ValueKey('uv-guidance-strip'),
                    padding: const EdgeInsets.all(10),
                    borderColor: uvInk.withValues(alpha: .2),
                    background: uvInk.withValues(alpha: .06),
                    child: Text(_summaryUvGuidance(level)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _departureHours == 0
                        ? 'Forecast · now'
                        : 'Forecast · in $_departureHours h',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (savedUv) const Text('Saved forecast · refresh available'),
                ],
              ),
            ),
          ),
        ),
        if (_busy || result?.weatherError != null || result?.alertError != null)
          DataStatus(
            loading: _busy,
            failed: result?.weatherError != null || result?.alertError != null,
            saved: weather != null || alerts != null,
            message: _busy
                ? 'Updating weather and alerts…'
                : 'Update incomplete · retry available',
            onRetry: _locating ? null : () => _load(manual: true),
          ),
        const SizedBox(height: 12),
        WeatherSection(
          key: const ValueKey('uv-advice-section'),
          borderColor: uvInk.withValues(alpha: .35),
          background: scheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: uvInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sun protection',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _UvOutdoorAdvice(level: level),
            ],
          ),
        ),
        const SizedBox(height: 12),
        weatherDetails,
        const SizedBox(height: 8),
        uvDetails,
        if (currentAlerts.isEmpty) alertCard,
        FilledButton.icon(
          onPressed: _busy || _locating ? null : () => _load(manual: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Check free weather & alerts'),
        ),
        const Center(child: Text('Open-Meteo · NWS')),
        ExpansionTile(
          key: const ValueKey('weather-controls'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Choose location and time'),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Saved map area'),
                  onPressed: () => _select(WeatherPlace.savedArea),
                ),
                if (widget.destination != null)
                  ActionChip(
                    label: const Text('Planned destination'),
                    onPressed: () => _select(
                      WeatherPlace(
                        label: widget.destination!.name,
                        coordinates: widget.destination!.location,
                      ),
                    ),
                  ),
                if (LocationScope.maybeOf(context) == null)
                  ActionChip(
                    label: Text(
                      _locating ? 'Finding location…' : 'Use device location',
                    ),
                    onPressed: _locating ? null : _deviceLocation,
                  ),
              ],
            ),
            if (_locationError != null) Text(_locationError!),
            Text(
              'Point: ${_place.coordinates.latitude.toStringAsFixed(5)}, '
              '${_place.coordinates.longitude.toStringAsFixed(5)}',
            ),
            const Text('Departure time (shown in this device’s local time):'),
            Wrap(
              spacing: 8,
              children: [
                for (final hours in [0, 1, 2, 4])
                  ChoiceChip(
                    label: Text(hours == 0 ? 'Now' : 'In $hours h'),
                    selected: _departureHours == hours,
                    onSelected: (_) => setState(() {
                      _departureHours = hours;
                      _requestId++;
                      _busy = false;
                      _departure = widget.clock().toUtc().add(
                        Duration(hours: hours),
                      );
                      _publishOverview();
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Update while the app is open'),
              subtitle: const Text(
                'Weather about every 15 min; alerts about every 5 min. Pauses in background.',
              ),
              value: _autoRefresh,
              onChanged: (value) => setState(() => _autoRefresh = value),
            ),
            TextButton(
              onPressed: () async {
                _requestId++;
                _started = false;
                await _repository.clear();
                if (mounted) {
                  setState(() {
                    _result = null;
                    _busy = false;
                  });
                  _publishOverview();
                }
              },
              child: const Text('Clear saved weather and alerts'),
            ),
          ],
        ),
      ],
    );
  }
}

String _summaryUvGuidance(UvLevel? level) => switch (level) {
  UvLevel.low => 'Low UV. Protect skin.',
  UvLevel.moderate => 'Seek midday shade.',
  UvLevel.high || UvLevel.veryHigh => 'Limit midday sun.',
  UvLevel.extreme => 'Avoid midday sun.',
  null => 'UV unavailable. Use sun protection.',
};

class _UvOutdoorAdvice extends StatelessWidget {
  const _UvOutdoorAdvice({required this.level});
  final UvLevel? level;

  @override
  Widget build(BuildContext context) {
    final outside = switch (level) {
      UvLevel.low => 'Take shade breaks if it’s hot.',
      UvLevel.moderate => 'Seek shade around midday.',
      UvLevel.high => 'Limit direct sun around midday.',
      UvLevel.veryHigh => 'Keep midday outings short; choose shade.',
      UvLevel.extreme => 'Avoid midday sun.',
      null => 'Take shade breaks; check UV before long outings.',
    };
    final tips = [
      ('Outside', outside),
      ('Water', 'Carry water and drink regularly in the heat.'),
      ('Clothing', 'Light, loose layers that cover skin; a hat.'),
      (
        'Sun protection',
        'UV-blocking sunglasses and broad-spectrum sunscreen. Reapply as directed.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tip in tips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${tip.$1}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: tip.$2),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _OfficialRecord extends StatelessWidget {
  const _OfficialRecord({required this.alert});
  final NwsAlert alert;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(alert.headline ?? alert.event),
    subtitle: Text(
      '${alert.severity} · ${alert.status} · ${alert.messageType}',
    ),
    children: [
      Text('Expires: ${_local(context, alert.expires)}'),
      ExpansionTile(
        title: const Text('Record details'),
        children: [
          SelectableText('NWS ID: ${alert.id}'),
          Text('Publisher: ${alert.senderName}'),
          Text('Sent: ${_local(context, alert.sent)}'),
          Text('Effective: ${_local(context, alert.effective)}'),
          if (alert.onset != null)
            Text('Onset: ${_local(context, alert.onset!)}'),
          if (alert.ends != null) Text('Ends: ${_local(context, alert.ends!)}'),
        ],
      ),
      SelectableText(alert.description ?? 'Description not supplied.'),
      SelectableText(alert.instruction ?? 'Instructions not supplied.'),
      SourceLink(
        label: 'Open official NWS record',
        url: alert.sourceUrl.toString(),
      ),
      TextButton(
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: alert.sourceUrl.toString())),
        child: const Text('Copy official NWS record link'),
      ),
    ],
  );
}

String _local(BuildContext context, DateTime value) {
  final at = value.toLocal();
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(at));
  return '${at.month}/${at.day}/${at.year} at $time';
}
