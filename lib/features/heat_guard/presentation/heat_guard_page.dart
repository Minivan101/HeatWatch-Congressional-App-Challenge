import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/feature_header.dart';
import '../models/heat_guard_contract.dart';
import '../../cool_spots/models/cooling_destination.dart';
import 'free_weather_preview.dart';
import '../services/weather_repository.dart';
import '../services/heat_guard_service.dart';

typedef HeatScenarioLoader = Future<Map<String, dynamic>> Function();

class HeatGuardPage extends StatefulWidget {
  const HeatGuardPage({
    super.key,
    this.scenarioLoader,
    this.service = const HeatGuardService(),
    this.destination,
    this.repository,
    this.active = true,
    this.autoStart = false,
    this.keepOverviewUpdated = false,
    this.savedPlaces,
    this.onShade,
    this.onCool,
  });

  final HeatScenarioLoader? scenarioLoader;
  final HeatGuardService service;
  final CoolingDestination? destination;
  final WeatherRepository? repository;
  final bool active, autoStart, keepOverviewUpdated;
  final VoidCallback? onShade, onCool;
  final Widget? savedPlaces;

  @override
  State<HeatGuardPage> createState() => _HeatGuardPageState();
}

class _HeatGuardPageState extends State<HeatGuardPage> {
  late Future<Map<String, dynamic>> _scenarios = _loadScenarios();
  String _selected = 'active';
  Map<String, dynamic>? _localFunctionExample;
  bool _loadingFunction = false;
  bool _functionFailed = false;
  bool _showDetailedReport = false;

  Future<void> _loadLocalFunctionExample() async {
    setState(() {
      _loadingFunction = true;
      _functionFailed = false;
      _localFunctionExample = null;
    });
    try {
      final data = await widget.service.getLocalExample();
      if (!mounted) return;
      setState(() => _localFunctionExample = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _functionFailed = true);
    } finally {
      if (mounted) setState(() => _loadingFunction = false);
    }
  }

  Future<Map<String, dynamic>> _loadScenarios() async {
    if (widget.scenarioLoader != null) {
      return HeatGuardContract.examples(await widget.scenarioLoader!());
    }
    final text = await rootBundle.loadString(
      'assets/heat_guard_scenarios.json',
    );
    return HeatGuardContract.examples(jsonDecode(text));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scenarioLoader == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FreeWeatherPreview(
            destination: widget.destination,
            repository: widget.repository,
            active: widget.active,
            autoStart: widget.autoStart,
            keepOverviewUpdated: widget.keepOverviewUpdated,
            home: true,
            savedPlaces: widget.savedPlaces,
            onShade: widget.onShade,
            onCool: widget.onCool,
            clock: widget.repository?.clock ?? DateTime.now,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const FeatureHeader(
          icon: Icons.health_and_safety,
          title: 'Heat Guard',
          description: 'See weather alerts, heat conditions, and UV guidance.',
        ),
        const SizedBox(height: 16),
        FreeWeatherPreview(
          destination: widget.destination,
          repository: widget.repository,
          active: widget.active,
          autoStart: widget.autoStart,
          keepOverviewUpdated: widget.keepOverviewUpdated,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              setState(() => _showDetailedReport = !_showDetailedReport),
          icon: Icon(
            _showDetailedReport ? Icons.expand_less : Icons.article_outlined,
          ),
          label: Text(
            _showDetailedReport
                ? 'Hide example scenarios'
                : 'View example scenarios',
          ),
        ),
        if (_showDetailedReport) ...[
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local Functions connection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Load a dated fictional example through the local '
                      'Functions emulator. This does not check current weather '
                      'or official alerts.',
                    ),
                    TextButton(
                      onPressed: _loadingFunction
                          ? null
                          : _loadLocalFunctionExample,
                      child: const Text('Load local Heat Guard example'),
                    ),
                    if (_loadingFunction)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Loading local Heat Guard example',
                      ),
                    if (_functionFailed)
                      const Text(
                        'Local Function unavailable. Start the Firebase '
                        'Functions emulator, then retry.',
                      ),
                    if (_localFunctionExample != null) ...[
                      const Text(
                        'Local Function responded with a fictional historical '
                        'example. No Weather API request was made.',
                      ),
                      HeatGuardScenario(
                        data:
                            _localFunctionExample!['scenario']
                                as Map<String, dynamic>,
                        exampleAsOf: DateTime.parse(
                          _localFunctionExample!['exampleAsOf'] as String,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Example Heat Guard scenarios',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fictional historical examples. No live weather '
                    'or official alerts were checked.',
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _scenarios,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Examples could not be loaded.'),
                            TextButton(
                              onPressed: () => setState(() {
                                _scenarios = _loadScenarios();
                              }),
                              child: const Text('Retry examples'),
                            ),
                          ],
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Column(
                          children: [
                            LinearProgressIndicator(
                              semanticsLabel: 'Loading Heat Guard examples',
                            ),
                            Text('Loading examples…'),
                          ],
                        );
                      }
                      final data = snapshot.data!;
                      if (data['sampleOnly'] != true ||
                          data['scenarios'] is! Map ||
                          data['exampleAsOf'] is! String) {
                        return const Text('Examples have incomplete data.');
                      }
                      final scenarios =
                          data['scenarios'] as Map<String, dynamic>;
                      final selected = scenarios[_selected];
                      if (selected is! Map<String, dynamic>) {
                        return const Text('Example is unavailable.');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final choice in const [
                                ('active', 'Active alert'),
                                ('checkedNone', 'Checked: none'),
                                ('unchecked', 'Not checked'),
                                ('stale', 'Outdated'),
                              ])
                                ChoiceChip(
                                  label: Text(choice.$2),
                                  selected: _selected == choice.$1,
                                  onSelected: (_) =>
                                      setState(() => _selected = choice.$1),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          HeatGuardScenario(
                            data: selected,
                            exampleAsOf: DateTime.parse(
                              data['exampleAsOf'] as String,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'HeatWatch provides general information, not emergency '
            'or personal medical advice. Follow official alerts.',
          ),
        ],
      ],
    );
  }
}

class HeatGuardScenario extends StatelessWidget {
  const HeatGuardScenario({
    required this.data,
    required this.exampleAsOf,
    super.key,
  });

  final Map<String, dynamic> data;
  final DateTime exampleAsOf;

  @override
  Widget build(BuildContext context) {
    final fetchedAt = DateTime.parse(data['fetchedAt'] as String);
    final age = exampleAsOf.difference(fetchedAt);
    final fresh = !age.isNegative && age <= const Duration(minutes: 30);
    final alertsChecked = data['alertsChecked'] == true;
    final alerts = (data['alerts'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where(
          (alert) =>
              DateTime.parse(alert['expiresAt'] as String).isAfter(exampleAsOf),
        )
        .toList();
    final current = data['current'] as Map<String, dynamic>;
    final guidance = (data['guidance'] as List<dynamic>).cast<String>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Example time: ${_formatLocalTime(context, exampleAsOf)}'),
        Text(
          fresh
              ? 'Example data age: ${age.inMinutes} minutes at example time.'
              : 'Example information is outdated at example time. '
                    'Do not use it for decisions.',
        ),
        const SizedBox(height: 8),
        if (!fresh)
          const Text('Alert status: example check is outdated.')
        else if (!alertsChecked)
          const Text('Alert status: not checked in this example.')
        else if (alerts.isEmpty)
          const Text('Alert status: no heat alerts in this simulated check.')
        else if (fresh)
          for (final alert in alerts) _ExampleAlertCard(alert: alert),
        const SizedBox(height: 8),
        Text(
          'Example temperature ${current['temperatureC']}°C · '
          'feels like ${current['feelsLikeC']}°C',
        ),
        Text(
          'Example UV Index ${current['uvIndex']} · '
          'humidity ${current['humidityPercent']}%',
        ),
        if (fresh) ...[
          const SizedBox(height: 8),
          Text(
            'General preparation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final message in guidance)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $message'),
            ),
          const Text(
            'Stay hydrated regularly. Consider reducing strenuous '
            'outdoor activity during dangerous heat.',
          ),
        ],
      ],
    );
  }
}

class _ExampleAlertCard extends StatelessWidget {
  const _ExampleAlertCard({required this.alert});

  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context) {
    final severity = alert['severity'] as String;
    final title = alert['title'] as String;
    return Semantics(
      label: 'Fictional example $severity heat alert: $title',
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    semanticLabel: 'Warning',
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Example $severity alert: $title')),
                ],
              ),
              Text(
                'Example expiry: ${_formatLocalTime(context, DateTime.parse(alert['expiresAt'] as String))}',
              ),
              Text('Fictional publisher: ${alert['source']}'),
              SelectableText(
                'Publisher website (not alert-specific): '
                '${alert['sourceUrl']}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatLocalTime(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '${local.month}/${local.day}/${local.year} at $time';
}
