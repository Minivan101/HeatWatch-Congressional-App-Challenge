import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'safety_page.dart';
import 'why_heatwatch_page.dart';
import '../location/app_location.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.settings});
  final AppSettings settings;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      label: Text(switch (mode) {
                        ThemeMode.system => 'System',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }),
                      selected: settings.themeMode == mode,
                      onSelected: (_) => settings.update(theme: mode),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Units', style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in [true, false])
                    ChoiceChip(
                      label: Text(f ? 'Imperial · °F, mi' : 'Metric · °C, km'),
                      selected: settings.imperial == f,
                      onSelected: (_) => settings.update(useImperial: f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Applies to weather, CoolSpots and walking directions. Saved on this device.',
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.favorite_outline),
                title: const Text('Why'),
                subtitle: const Text('Our purpose & community impact'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WhyHeatWatchPage(),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Warnings & safety'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SafetyPage()),
                ),
              ),
              if (LocationScope.maybeOf(context) case final location?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Location access'),
                  subtitle: Text(
                    [
                      location.status,
                      if (location.error != null) location.error!,
                    ].join('\n'),
                  ),
                  onTap: () => showLocationChoice(context, location),
                ),
              if (settings.saveError != null) Text(settings.saveError!),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
