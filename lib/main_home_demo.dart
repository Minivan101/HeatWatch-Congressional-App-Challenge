import 'package:flutter/material.dart';

import 'app.dart';
import 'core/settings/app_settings.dart';
import 'features/heat_guard/demo/home_demo_data.dart';
import 'features/heat_guard/services/weather_repository.dart';
import 'features/heat_guard/services/weather_cache_memory.dart';

void main() => runApp(const HomeDemo());

class HomeDemo extends StatefulWidget {
  const HomeDemo({super.key});
  @override
  State<HomeDemo> createState() => _HomeDemoState();
}

class _HomeDemoState extends State<HomeDemo> {
  String scenario = 'Sunny / high UV';
  late WeatherRepository repository = createRepository();
  final settings = AppSettings(
    read: () async => ' {"fahrenheit":true,"location":"never","theme":"light"}',
    write: (_) async {},
  );
  WeatherRepository createRepository() {
    final hour = switch (scenario) {
      'Sunrise' => 12,
      'Sunset' => 3,
      'Night / moon' => 6,
      _ => 20,
    };
    final now = DateTime.utc(
      2026,
      7,
      hour < 7 ? 11 : 10,
      hour,
      hour == 12 ? 30 : 0,
    );
    return WeatherRepository(
      clock: () => now,
      cache: WeatherCache(),
      weather: HomeDemoWeather(
        now,
        unavailable: scenario == 'Provider outage',
        stale: scenario == 'Saved / stale',
        mild: scenario == 'Mild conditions',
      ),
      alerts: HomeDemoAlerts(
        now,
        warning: scenario == 'Active warning',
        unavailable: scenario == 'Provider outage',
      ),
    );
  }

  @override
  void dispose() {
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HeatWatchApp(
    key: ValueKey(scenario),
    settings: settings,
    weatherRepository: repository,
    promptLocation: false,
    mapTilesEnabled: false,
    demoControls: Material(
      color: const Color(0xFFFFE7B6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'SIMULATED DEMO DATA\nDesign review · July 10, 2026',
                style: TextStyle(
                  color: Color(0xFF513700),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DropdownButton<String>(
              value: scenario,
              items: [
                for (final s in const [
                  'Sunny / high UV',
                  'Sunrise',
                  'Sunset',
                  'Night / moon',
                  'Active warning',
                  'Mild conditions',
                  'Saved / stale',
                  'Provider outage',
                ])
                  DropdownMenuItem(
                    value: s,
                    child: Text(s, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (s) {
                if (s != null) {
                  setState(() {
                    scenario = s;
                    repository = createRepository();
                  });
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
