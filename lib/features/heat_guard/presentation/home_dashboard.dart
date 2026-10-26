import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../models/free_weather.dart';
import '../models/home_weather.dart';
import '../models/uv_level.dart';
import '../models/weather_condition.dart';
import '../services/alert_lifecycle.dart';
import 'weather_visuals.dart' show weatherConditionIcon;
import 'weather_guidance.dart';

abstract final class HomeStyle {
  static const navy = Color(0xFF10283F), teal = Color(0xFF007A7A);
  static const canvas = Color(0xFFF3F7FA), muted = Color(0xFF52677C);
  static const orange = Color(0xFFF58B45);
}

String homeTemperature(BuildContext context, double? c) {
  final f = SettingsScope.maybeOf(context)?.fahrenheit ?? true;
  return c == null
      ? '—°'
      : '${(f ? c * 9 / 5 + 32 : c).round()}°${f ? 'F' : 'C'}';
}

IconData homeSkyIcon(WeatherReading? weather, DateTime now) {
  if (weather == null) return Icons.cloud_outlined;
  final phase = solarPhase(weather, now);
  if ([
    WeatherSky.clear,
    WeatherSky.mainlyClear,
  ].contains(weather.condition.sky)) {
    return switch (phase) {
      SolarPhase.night => Icons.nightlight_round,
      SolarPhase.sunrise || SolarPhase.sunset => Icons.wb_twilight,
      SolarPhase.unknown => weatherConditionIcon(weather.condition),
      _ => Icons.wb_sunny_outlined,
    };
  }
  return weatherConditionIcon(weather.condition);
}

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    super.key,
    required this.result,
    required this.place,
    required this.now,
    required this.loading,
    required this.onRefresh,
    required this.onLocation,
    this.savedPlaces,
    this.onShade,
    this.onCool,
  });
  final FreeWeatherResult? result;
  final WeatherPlace place;
  final DateTime now;
  final bool loading;
  final VoidCallback onRefresh, onLocation;
  final VoidCallback? onShade, onCool;
  final Widget? savedPlaces;
  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  bool hourly = false;
  final GlobalKey _alertKey = GlobalKey();
  bool expandAlert = false;
  @override
  Widget build(BuildContext context) {
    final r = widget.result, w = r?.weather, now = widget.now;
    final warnings = r?.alerts == null
        ? <NwsAlert>[]
        : activeAlerts(r!.alerts!, now);
    final recs = recommendations(
      r,
      now,
      imperial: SettingsScope.maybeOf(context)?.imperial ?? true,
    );
    final fresh = w != null && w.currentFreshAt(now) && r?.weatherError == null;
    final forecastFresh =
        w != null && w.forecastFreshAt(now) && r?.weatherError == null;
    final uv = w?.uvFor(now), level = UvLevel.fromValue(uv?.value);
    final time = PlaceTime(w);
    final daily = w == null ? null : todayConditions(w, now);
    final date = time.date(now);
    DailyUv? dailyUv;
    for (final d in w?.dailyUv ?? <DailyUv>[]) {
      if (d.localDate == date) dailyUv = d;
    }
    final todayUv = (w?.hourlyUv ?? <TimedUv>[])
        .where((u) => time.date(u.validAt) == date && u.value != null)
        .toList();
    final peakHour = todayUv.isEmpty
        ? null
        : todayUv.reduce((a, b) => a.value! >= b.value! ? a : b);
    final advice = fresh
        ? recs
        : recs
              .where((r) => r.category == 'official' || r.category == 'sun')
              .toList();
    void showDetails(Widget child) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );
    }

    final uvDetails = _Panel(
      key: const ValueKey('home-uv-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'UV Index',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(homeSkyIcon(w, now), color: HomeStyle.teal),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                uv?.value?.toStringAsFixed(1) ?? '—',
                key: const ValueKey('home-uv-value'),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                level?.label ?? 'Unavailable',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          Text(
            uv == null
                ? 'Current-hour forecast unavailable'
                : '${forecastFresh ? 'Forecast' : 'Saved forecast'} · ${time.hour(uv.validAt)} hour',
            style: const TextStyle(color: HomeStyle.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          UvSpectrum(value: uv?.value),
          const SizedBox(height: 12),
          Text(
            'Today’s forecast peak: ${dailyUv?.maximum?.toStringAsFixed(1) ?? '—'}${peakHour != null && peakHour.value == dailyUv?.maximum ? ' · ${time.hour(peakHour.validAt)}' : ''}',
            style: const TextStyle(color: HomeStyle.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HomeStyle.canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(uvAdvice(level)),
          ),
          ExpansionTile(
            title: const Text('UV details'),
            tilePadding: EdgeInsets.zero,
            children: [
              const Text(
                'Low 0–2 · Moderate 3–5 · High 6–7\nVery high 8–10 · Extreme 11+',
              ),
              const SizedBox(height: 12),
              const Text(
                'Use shade, protective clothing, a hat, UV-blocking sunglasses and broad-spectrum SPF 30+ sunscreen outdoors. Reapply as directed.',
              ),
              if (todayUv.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Hourly outlook: ${todayUv.where((u) => !u.validAt.isBefore(now.subtract(const Duration(hours: 1)))).take(8).map((u) => '${time.hour(u.validAt)} ${u.value!.toStringAsFixed(1)}').join(' · ')}',
                  ),
                ),
              const Text(
                'Hourly modeled forecast, not a measured personal exposure. Daily peak is a separate forecast; low UV does not mean low heat.',
              ),
              const SourceLink(
                label: 'EPA UV scale & protection',
                url: 'https://www.epa.gov/sunsafety/uv-index-scale-0',
              ),
              const SourceLink(
                label: 'CDC sun protection',
                url: 'https://www.cdc.gov/skin-cancer/sun-safety/index.html',
              ),
            ],
          ),
        ],
      ),
    );
    final weatherDetails = _Panel(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Weather details'),
        initiallyExpanded: true,
        children: [
          Text('Selected point: ${widget.place.label}'),
          Text(
            'Times: ${w?.timezone ?? 'America/Los_Angeles'}${time.zone == null ? ' (fixed-offset fallback)' : ''}',
          ),
          if (daily?.sunrise != null)
            Text(
              'Sunrise ${time.hour(daily!.sunrise!)} · Sunset ${time.hour(daily.sunset!)}',
            ),
          if (w != null)
            Text(
              'Retrieved ${time.date(w.fetchedAt)} at ${time.hour(w.fetchedAt)}',
            ),
          const Text(
            'Open-Meteo modeled conditions and forecasts. NWS alerts are checked separately. Official HeatRisk and AQI are not available in the connected providers.',
          ),
          if (w != null && w.issues.isNotEmpty) Text(w.issues.join('\n')),
          if (r?.cacheNotice != null) Text(r!.cacheNotice!),
          const SourceLink(
            label: 'Open-Meteo · CC BY 4.0',
            url: 'https://open-meteo.com/',
          ),
          const SourceLink(
            label: 'NWS alerts',
            url: 'https://www.weather.gov/documentation/services-web-api',
          ),
          const SourceLink(
            label: 'CDC heat guidance',
            url: 'https://www.cdc.gov/heat-health/about/index.html',
          ),
          TextButton(
            onPressed: widget.onLocation,
            child: const Text('Change weather location'),
          ),
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConditionsHero(
              weather: w,
              now: now,
              loading: widget.loading,
              stale: !fresh,
              onDetails: () => showDetails(weatherDetails),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final columns = MediaQuery.textScalerOf(context).scale(14) > 21
                    ? 1
                    : 3;
                final width = (c.maxWidth - 10 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SummaryMetric(
                      width: width,
                      icon: Icons.wb_sunny_outlined,
                      title: 'UV Index',
                      value: uv?.value?.toStringAsFixed(1) ?? '—',
                      note: level?.label ?? 'Unavailable',
                      color: const Color(0xFFB74919),
                      onTap: () => showDetails(uvDetails),
                    ),
                    _SummaryMetric(
                      width: width,
                      icon: Icons.air,
                      title: 'Wind',
                      value: w?.windKmh == null
                          ? '—'
                          : '${((SettingsScope.maybeOf(context)?.imperial ?? true) ? w!.windKmh! / 1.609344 : w!.windKmh!).round()}',
                      note: (SettingsScope.maybeOf(context)?.imperial ?? true)
                          ? 'mph'
                          : 'km/h',
                      color: HomeStyle.teal,
                    ),
                    _SummaryMetric(
                      width: width,
                      icon: Icons.water_drop,
                      title: 'Humidity',
                      value: w?.humidityPercent == null
                          ? '—'
                          : '${w!.humidityPercent!.round()}%',
                      note: 'Relative humidity',
                      color: const Color(0xFF00668D),
                    ),
                  ],
                );
              },
            ),
            if (widget.savedPlaces != null) ...[
              const SizedBox(height: 12),
              widget.savedPlaces!,
            ],
            if (widget.loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                semanticsLabel: 'Updating weather and alerts',
              ),
            ],
            if (r?.weatherError != null || r?.alertError != null) ...[
              const SizedBox(height: 12),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w == null
                          ? 'Weather unavailable'
                          : 'Showing saved weather',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (r?.weatherError != null)
                      const Text(
                        'Weather update failed. Retry when connected.',
                      ),
                    if (r?.alertError != null)
                      const Text(
                        'Official alert check unavailable. This does not mean there are no alerts.',
                      ),
                    TextButton(
                      onPressed: widget.onRefresh,
                      child: const Text('Retry update'),
                    ),
                  ],
                ),
              ),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final a in warnings)
                _Panel(
                  key: identical(a, warnings.first)
                      ? _alertKey
                      : ValueKey(a.id),
                  color: const Color(0xFFFFF0EC),
                  child: ExpansionTile(
                    key: ValueKey('${a.id}-$expandAlert'),
                    initiallyExpanded: expandAlert,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    leading: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFF9A3027),
                    ),
                    title: Text(
                      a.event,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${a.severity} · ${time.hour(a.effective)}–${time.hour(a.ends ?? a.expires)}\n${!r!.alerts!.freshAt(now) || r.alertError != null ? 'Saved alert · check again' : 'National Weather Service'}',
                    ),
                    children: [
                      Text(
                        a.headline ?? a.event,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Issuer: ${a.senderName}'),
                      Text(
                        'Effective: ${time.date(a.effective)} ${time.hour(a.effective)}',
                      ),
                      Text(
                        'Expires: ${time.date(a.expires)} ${time.hour(a.expires)}',
                      ),
                      if ((a.raw['properties'] as Map?)?['areaDesc']
                          case final String area)
                        Text('Affected area: $area'),
                      const SizedBox(height: 8),
                      SelectableText(
                        a.description ?? 'Description not supplied.',
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        a.instruction ?? 'Instructions not supplied.',
                      ),
                      SourceLink(
                        label: 'Official NWS record',
                        url: a.sourceUrl.toString(),
                      ),
                    ],
                  ),
                ),
            ] else if (!widget.loading &&
                (r?.alerts == null || r?.alertError != null))
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Official alerts unavailable. Refresh to check.',
                  style: TextStyle(color: HomeStyle.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 24),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading(hourly ? 'Hourly Forecast' : 'Today’s Forecast'),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Dayparts'),
                        icon: Icon(Icons.view_day_outlined),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Hourly'),
                        icon: Icon(Icons.schedule),
                      ),
                    ],
                    selected: {hourly},
                    onSelectionChanged: (v) => setState(() => hourly = v.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  if (w == null)
                    _Panel(
                      child: Text(
                        widget.loading ? 'Loading forecast…' : 'Forecast unavailable. Choose a location or retry.',
                      ),
                    )
                  else ...[
                    if (!forecastFresh)
                      const Text(
                        'Saved forecast · may be outdated',
                        style: TextStyle(color: HomeStyle.muted),
                      ),
                    ForecastOverview(weather: w, now: now, hourly: hourly),
                    const SizedBox(height: 10),
                    Text(
                      forecastInsight(w, now),
                      style: const TextStyle(
                        color: HomeStyle.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading('Today’s Recommendations'),
                  const SizedBox(height: 12),
                  if (advice.isEmpty)
                    Text(
                      w == null || !fresh
                          ? 'Refresh conditions before planning an outdoor outing.'
                          : 'Not enough current detail for tailored advice. Check conditions before heading out.',
                    ),
                  LayoutBuilder(
                    builder: (context, c) {
                      final textScale =
                          (MediaQuery.textScalerOf(context).scale(14) / 14)
                              .clamp(1.0, 2.0);
                      final available = (c.maxWidth / (230 * textScale))
                          .floor()
                          .clamp(1, 3);
                      final columns = advice.length == 4 && available >= 2
                          ? 2
                          : available.clamp(1, math.max(1, advice.length));
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < advice.length; i++)
                            SizedBox(
                              width: (c.maxWidth - 8 * (columns - 1)) / columns,
                              child: _RecommendationRow(
                                item: advice[i],
                                onTap: advice[i].action == 'cool'
                                    ? widget.onCool
                                    : advice[i].action == 'shade'
                                    ? widget.onShade
                                    : advice[i].action == 'alert'
                                    ? () {
                                        setState(() => expandAlert = true);
                                        Scrollable.ensureVisible(
                                          _alertKey.currentContext!,
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 200,
                                                ),
                                        );
                                      }
                                    : null,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final stacked =
                    c.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(14) > 21;
                final width = stacked ? c.maxWidth : (c.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _ActionCard(
                        icon: Icons.route,
                        title: 'Open ShadeMap',
                        detail: '',
                        onTap: widget.onShade,
                        color: const Color(0xFFC94620),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _ActionCard(
                        icon: Icons.ac_unit,
                        title: 'Find Cool Spots',
                        detail: '',
                        onTap: widget.onCool,
                      ),
                    ),
                  ],
                );
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.loading ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

Widget _heading(String title, {String? subtitle}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
    if (subtitle != null)
      Text(
        subtitle,
        style: const TextStyle(color: HomeStyle.muted, fontSize: 12),
      ),
  ],
);

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: HomeStyle.teal),
      useMaterial3: true,
    ),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE0E8EE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: HomeStyle.navy),
          child: IconTheme(
            data: const IconThemeData(color: HomeStyle.muted),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class ConditionsHero extends StatelessWidget {
  const ConditionsHero({
    super.key,
    required this.weather,
    required this.now,
    required this.loading,
    required this.stale,
    required this.onDetails,
  });
  final WeatherReading? weather;
  final DateTime now;
  final bool loading, stale;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final w = weather,
        phase = solarPhase(w, now),
        night = phase == SolarPhase.night;
    final daily = w == null ? null : todayConditions(w, now);
    final colors = night
        ? const [Color(0xFF10283F), Color(0xFF253F68)]
        : phase == SolarPhase.sunrise || phase == SolarPhase.sunset
        ? const [Color(0xFFFFDFB6), Color(0xFFF8BC83)]
        : const [Color(0xFFFFF6E6), Color(0xFFFFB17F)];
    final ink = night ? Colors.white : HomeStyle.navy;
    return Container(
      key: const ValueKey('home-conditions'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _VegasBackdrop(night: night)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: DefaultTextStyle(
              style: TextStyle(color: ink, fontSize: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'CURRENT CONDITIONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Weather details',
                        onPressed: onDetails,
                        icon: Icon(Icons.chevron_right, color: ink),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        homeTemperature(context, w?.temperatureC),
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -3,
                          height: 1.1,
                        ),
                      ),
                      Icon(
                        homeSkyIcon(w, now),
                        color: night ? Colors.white : const Color(0xFFD86510),
                        size: 38,
                      ),
                      Text(
                        w?.condition.label ??
                            (loading ? 'Updating…' : 'Weather unavailable'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Feels like ${homeTemperature(context, w?.feelsLikeC)}  ·  H ${homeTemperature(context, daily?.highC)}  L ${homeTemperature(context, daily?.lowC)}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    w?.temperatureC == null
                        ? 'Choose a location or refresh to check conditions.'
                        : stale
                        ? 'Saved reading · refresh before planning.'
                        : math.max(
                                w!.temperatureC!,
                                w.feelsLikeC ?? w.temperatureC!,
                              ) >=
                              32
                        ? 'Hot conditions. Plan cooling breaks outdoors.'
                        : 'Check the forecast before heading outdoors.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

WeatherCondition _hourCondition(WeatherReading reading, TimedConditions hour) {
  final solar = todayConditions(reading, hour.validAt);
  return WeatherCondition.fromCode(
    hour.weatherCode,
    isDay: solar?.sunrise == null || solar?.sunset == null
        ? null
        : !hour.validAt.isBefore(solar!.sunrise!) &&
              hour.validAt.isBefore(solar.sunset!),
  );
}

class ForecastOverview extends StatelessWidget {
  const ForecastOverview({
    super.key,
    required this.weather,
    required this.now,
    required this.hourly,
  });
  final WeatherReading weather;
  final DateTime now;
  final bool hourly;
  @override
  Widget build(BuildContext context) {
    final time = PlaceTime(weather),
        periods = dayparts(weather, now),
        hours = upcomingHours(weather, now);
    final cards = <Widget>[];
    if (hourly) {
      for (final h in hours) {
        cards.add(
          _forecastCard(
            context,
            time.hour(h.validAt),
            h.temperatureC,
            _hourCondition(weather, h),
            h.validAt.isBefore(now),
            'Forecast',
          ),
        );
      }
    } else {
      for (final p in periods) {
        cards.add(
          _forecastCard(
            context,
            p.label,
            p.averageC,
            _hourCondition(weather, p.hours[p.hours.length ~/ 2]),
            p.current,
            p.warmest ? 'Warmest' : 'Average',
          ),
        );
      }
    }
    if (cards.isEmpty) {
      return const _Panel(
        child: Text('Temperature forecast unavailable for this period.'),
      );
    }
    return Column(
      children: [
        if (hourly && hours.where((h) => h.temperatureC != null).length >= 2)
          SizedBox(
            height: 80,
            child: Semantics(
              label: 'Hourly temperature trend. Exact forecast temperatures are in the cards below.',
              image: true,
              child: CustomPaint(
                painter: _TemperatureLine(hours),
                size: const Size(double.infinity, 80),
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards,
          ),
        ),
      ],
    );
  }

  Widget _forecastCard(
    BuildContext context,
    String label,
    double? c,
    WeatherCondition condition,
    bool current,
    String status,
  ) => Container(
    width: MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 170 : 128,
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: BoxDecoration(
      color: current ? const Color(0xFFE2F3F3) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: current ? HomeStyle.teal : const Color(0xFFE0E8EE),
      ),
    ),
    child: Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: HomeStyle.navy,
          ),
        ),
        const SizedBox(height: 10),
        Icon(weatherConditionIcon(condition), color: HomeStyle.teal, size: 26),
        const SizedBox(height: 8),
        Text(
          homeTemperature(context, c),
          style: const TextStyle(
            color: HomeStyle.navy,
            fontSize: 23,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          current ? 'Current · $status' : status,
          style: const TextStyle(color: HomeStyle.muted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _TemperatureLine extends CustomPainter {
  _TemperatureLine(this.hours);
  final List<TimedConditions> hours;
  @override
  void paint(Canvas canvas, Size size) {
    final values = hours
        .where((h) => h.temperatureC != null)
        .map((h) => h.temperatureC!)
        .toList();
    if (values.length < 2) return;
    final low = values.reduce(math.min),
        high = values.reduce(math.max),
        range = math.max(1.0, high - low);
    final path = Path();

    var segment = false;
    for (var i = 0; i < hours.length; i++) {
      final v = hours[i].temperatureC;
      if (v == null) {
        segment = false;
        continue;
      }
      final x = 8 + i * (size.width - 16) / (hours.length - 1),
          y = size.height - 12 - (v - low) * (size.height - 24) / range;
      if (!segment) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      segment = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = HomeStyle.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_TemperatureLine old) => old.hours != hours;
}

class UvSpectrum extends StatelessWidget {
  const UvSpectrum({super.key, required this.value});
  final double? value;
  @override
  Widget build(BuildContext context) {
    final band = UvLevel.fromValue(value)?.index;
    const colors = [
      Color(0xFF237C41),
      Color(0xFFF0CF40),
      Color(0xFFEF8A35),
      Color(0xFFC74442),
      Color(0xFF82489B),
    ];
    return Semantics(
      label: band == null
          ? 'UV category unavailable'
          : 'UV ${value!.toStringAsFixed(1)} ${UvLevel.values[band].label}',
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 18,
                    child: band == i
                        ? const Icon(
                            Icons.arrow_drop_down,
                            color: HomeStyle.navy,
                            size: 22,
                          )
                        : null,
                  ),
                  Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ['0–2', '3–5', '6–7', '8–10', '11+'][i],
                    style: const TextStyle(
                      fontSize: 11,
                      color: HomeStyle.muted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({required this.item, this.onTap});
  final HomeRecommendation item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final icon = switch (item.category) {
      'official' => Icons.warning_amber_rounded,
      'hydration' => Icons.water_drop_outlined,
      'sun' => Icons.wb_sunny_outlined,
      'cooling' => Icons.ac_unit,
      'clothing' => Icons.checkroom_outlined,
      'wind' => Icons.air,
      'storm' => Icons.thunderstorm_outlined,
      'rain' => Icons.umbrella_outlined,
      'weather' => Icons.visibility_outlined,
      _ => Icons.event_outlined,
    };
    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: HomeStyle.canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: HomeStyle.teal, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (item.condition != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.condition!,
                      style: const TextStyle(
                        color: HomeStyle.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          item.detail,
          style: const TextStyle(color: HomeStyle.muted, fontSize: 13),
        ),
      ],
    );
    return onTap == null
        ? Padding(
            key: ValueKey('recommendation-${item.ruleId}'),
            padding: const EdgeInsets.all(8),
            child: row,
          )
        : InkWell(
            key: ValueKey('recommendation-${item.ruleId}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(padding: const EdgeInsets.all(8), child: row),
          );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
    this.color = const Color(0xFF006585),
  });
  final Color color;
  final IconData icon;
  final String title, detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      style: const TextStyle(
                        color: HomeStyle.muted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.note,
    required this.color,
    this.onTap,
  });
  final double width;
  final IconData icon;
  final String title, value, note;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _Panel(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(color: HomeStyle.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              key: title == 'UV Index' ? const ValueKey('home-uv-value') : null,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            Text(
              note,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'UV details',
                  style: TextStyle(fontSize: 12, color: HomeStyle.muted),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _VegasBackdrop extends CustomPainter {
  const _VegasBackdrop({required this.night});
  final bool night;
  @override
  void paint(Canvas canvas, Size size) {
    final sun = Paint()
      ..color = (night ? const Color(0xFFE9F1FF) : const Color(0xFFFFEDB1))
          .withValues(alpha: .8);
    canvas.drawCircle(Offset(size.width * .86, size.height * .28), 23, sun);
    final mountains = Path()..moveTo(size.width * .43, size.height);
    for (final p in const [
      Offset(.43, .68),
      Offset(.53, .53),
      Offset(.60, .61),
      Offset(.67, .48),
      Offset(.77, .60),
      Offset(.88, .51),
      Offset(1, .65),
    ]) {
      mountains.lineTo(size.width * p.dx, size.height * p.dy);
    }
    mountains.lineTo(size.width, size.height);
    mountains.close();
    canvas.drawPath(
      mountains,
      Paint()
        ..color = (night ? const Color(0xFF8DA3CD) : const Color(0xFFB97356))
            .withValues(alpha: .15),
    );
    final buildings = Paint()
      ..color = (night ? const Color(0xFF526C94) : const Color(0xFFC6744E))
          .withValues(alpha: .18);
    for (var i = 0; i < 8; i++) {
      final x = size.width * (.58 + i * .055);
      final h = size.height * (.16 + (i % 3) * .05);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, size.width * .045, h),
          const Radius.circular(2),
        ),
        buildings,
      );
    }
    final towerX = size.width * .94;
    canvas.drawRect(
      Rect.fromLTWH(towerX - 3, size.height * .44, 6, size.height * .56),
      buildings,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(towerX, size.height * .45),
        width: 25,
        height: 10,
      ),
      buildings,
    );
    canvas.drawLine(
      Offset(towerX, size.height * .30),
      Offset(towerX, size.height * .44),
      Paint()
        ..color = buildings.color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_VegasBackdrop oldDelegate) => oldDelegate.night != night;
}
