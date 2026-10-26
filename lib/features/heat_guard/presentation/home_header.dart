import 'package:flutter/material.dart';

import 'weather_overview.dart';
import 'home_dashboard.dart';
import '../models/free_weather.dart';

class HomeHeaderLocation extends StatelessWidget {
  const HomeHeaderLocation({super.key, this.onHome});
  final VoidCallback? onHome;
  @override
  Widget build(BuildContext context) {
    final overview = WeatherOverviewScope.maybeOf(context);
    final place = overview?.place;
    final label = place == null || place.label == WeatherPlace.savedArea.label
        ? 'Las Vegas, NV'
        : place.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          key: const ValueKey('home-logo'),
          onTap: onHome,
          borderRadius: BorderRadius.circular(8),
          child: Semantics(
            button: true,
            label: 'HeatWatch home',
            child: const SizedBox(
              height: 44,
              child: Row(
                children: [
                  Icon(Icons.wb_twilight, color: Color(0xFFE97027), size: 26),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'HeatWatch',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            backgroundColor: HomeStyle.canvas,
            foregroundColor: HomeStyle.navy,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(44, 44),
            shape: const StadiumBorder(),
          ),
          onPressed: overview?.chooseLocation,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class HomeHeaderTemperature extends StatelessWidget {
  const HomeHeaderTemperature({
    super.key,
    this.onOpen,
    this.clock = DateTime.now,
  });
  final VoidCallback? onOpen;
  final DateTime Function() clock;
  @override
  Widget build(BuildContext context) {
    final overview = WeatherOverviewScope.maybeOf(context),
        w = overview?.result?.weather,
        now = clock().toUtc();
    final saved =
        w != null &&
        (!w.currentFreshAt(now) || overview?.result?.weatherError != null);
    return Semantics(
      label:
          '${saved ? 'Saved temperature' : 'Current modeled temperature'}, ${w?.condition.label ?? 'unavailable'}',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                homeSkyIcon(w, now),
                key: const ValueKey('persistent-weather-icon'),
                size: 30,
                color: HomeStyle.teal,
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    homeTemperature(context, w?.temperatureC),
                    key: const ValueKey('persistent-temperature'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (saved)
                    const Text('Saved', style: TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
