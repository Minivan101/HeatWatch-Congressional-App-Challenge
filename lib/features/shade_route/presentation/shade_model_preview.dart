import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/shade_route_service.dart';
import 'route_sketch.dart';

class ShadeModelPreview extends StatefulWidget {
  const ShadeModelPreview({
    super.key,
    this.service = const ShadeRouteService(),
  });

  final ShadeRouteService service;

  @override
  State<ShadeModelPreview> createState() => _ShadeModelPreviewState();
}

class _ShadeModelPreviewState extends State<ShadeModelPreview> {
  late Future<_RouteResult> _sample = _loadSample();
  final TextEditingController _destinationController = TextEditingController(
    text: 'Demo destination',
  );
  bool _destinationSelected = true;
  bool _fromEmulator = false;
  bool _checkingEmulator = false;
  bool _routeRequestFailed = false;
  String? _emulatorError;
  String? _selectedRouteId;

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<_RouteResult> _loadSample() async {
    final text = await rootBundle.loadString('assets/shade_demo.json');
    return _parseSample(jsonDecode(text) as Map<String, dynamic>);
  }

  _RouteResult _parseSample(Map<String, dynamic> data) {
    if (data['sampleOnly'] != true ||
        data['routes'] is! List ||
        data['choices'] is! Map ||
        data['destination'] is! Map ||
        data['origin'] is! Map ||
        data['departureTime'] is! String ||
        data['timeZoneId'] is! String ||
        (data['timeZoneId'] as String).isEmpty) {
      throw const FormatException('Incomplete labeled route sample');
    }
    try {
      final routes = (data['routes'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_RoutePreview.fromJson)
          .toList();
      final ids = routes.map((route) => route.id).toSet();
      final choices = Map<String, dynamic>.from(data['choices'] as Map);
      if (routes.isEmpty ||
          ids.length != routes.length ||
          !ids.contains(choices['fastest']) ||
          (choices['balanced'] != null && !ids.contains(choices['balanced'])) ||
          (choices['mostShade'] != null &&
              !ids.contains(choices['mostShade']))) {
        throw const FormatException('Sample route choice is missing');
      }
      final destination = Map<String, dynamic>.from(data['destination'] as Map);
      final label = destination['label'];
      if (label is! String || label.trim().isEmpty) {
        throw const FormatException('Sample destination is missing');
      }
      return _RouteResult(
        routes,
        choices,
        label,
        ShadeRouteTrip.fromDemoAsset(data),
        data['timeZoneId'] as String,
      );
    } catch (_) {
      throw const FormatException('Incomplete route sample');
    }
  }

  Future<void> _checkEmulator() async {
    if (!_destinationSelected) return;
    setState(() {
      _checkingEmulator = true;
      _routeRequestFailed = false;
      _emulatorError = null;
    });
    try {
      final savedTrip = (await _sample).trip;
      final data = await widget.service.getDemoRoutes(savedTrip);
      final result = _parseSample(data);
      if (!mounted) return;
      setState(() {
        _sample = Future.value(result);
        _fromEmulator = true;
        _selectedRouteId = null;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _routeRequestFailed = true;
        _fromEmulator = false;
        _emulatorError = 'The local backend returned incomplete route data.';
      });
    } on ShadeRouteFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _routeRequestFailed = true;
        _fromEmulator = false;
        _emulatorError = switch (error.kind) {
          ShadeRouteFailureKind.invalidTrip =>
            'This trip is not available in the saved demo.',
          ShadeRouteFailureKind.noRoutes =>
            'No walking routes were returned for this trip.',
          ShadeRouteFailureKind.outsideBuildingCoverage =>
            'Building data does not cover this trip area.',
          ShadeRouteFailureKind.unavailable =>
            'Could not reach the local demo. Start the Firebase '
                'Functions emulator, then try again.',
          ShadeRouteFailureKind.invalidResponse =>
            'The local backend returned incomplete route data.',
        };
      });
    } catch (error) {
      debugPrint('Local backend demo failed: $error');
      if (!mounted) return;
      setState(() {
        _routeRequestFailed = true;
        _fromEmulator = false;
        _emulatorError = 'Could not read the local route demo.';
      });
    } finally {
      if (mounted) setState(() => _checkingEmulator = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shade route choices (demo)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sample only · Not walking directions. Route lines are invented; '
              'building footprints come from a saved OpenStreetMap extract.',
            ),
            const SizedBox(height: 12),
            FutureBuilder<_RouteResult>(
              future: _sample,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Could not load the sample estimate.');
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final result = snapshot.data!;
                final selectedId =
                    _selectedRouteId ?? result.choices['fastest'];
                final selected = result.routes.firstWhere(
                  (route) => route.id == selectedId,
                  orElse: () => result.routes.first,
                );
                final selectedNumber = result.routes.indexOf(selected) + 1;
                final searchMatches = result.destinationLabel
                    .toLowerCase()
                    .contains(_destinationController.text.trim().toLowerCase());
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('demo_destination_field'),
                      controller: _destinationController,
                      decoration: const InputDecoration(
                        labelText: 'Search demo destination',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {
                        _destinationSelected = false;
                        _fromEmulator = false;
                        _routeRequestFailed = false;
                        _emulatorError = null;
                        _selectedRouteId = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    if (_destinationSelected)
                      Text(
                        'Selected demo destination: ${result.destinationLabel}',
                      )
                    else if (searchMatches)
                      ListTile(
                        key: const Key('demo_destination_suggestion'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(result.destinationLabel),
                        subtitle: const Text('Saved demo destination'),
                        onTap: () => setState(() {
                          _destinationController.text = result.destinationLabel;
                          _destinationSelected = true;
                          _routeRequestFailed = false;
                        }),
                      )
                    else
                      const Text(
                        'No saved demo destination matches. Live destination '
                        'search is not enabled yet.',
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _destinationSelected && !_checkingEmulator
                          ? _checkEmulator
                          : null,
                      icon: _checkingEmulator
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _checkingEmulator
                            ? 'Checking saved trip…'
                            : 'Send saved trip to local backend',
                      ),
                    ),
                    if (_checkingEmulator)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Checking local route demo',
                      ),
                    if (_fromEmulator)
                      const Text(
                        'Confirmed: saved trip matched the local '
                        'Firebase Functions demo.',
                      ),
                    if (_emulatorError != null)
                      Text(
                        _emulatorError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_destinationSelected &&
                        !_checkingEmulator &&
                        !_routeRequestFailed) ...[
                      const SizedBox(height: 12),
                      for (var i = 0; i < result.routes.length; i++) ...[
                        _RouteChoiceCard(
                          route: result.routes[i],
                          number: i + 1,
                          choices: result.choices,
                          selected: result.routes[i].id == selected.id,
                          onTap: () => setState(
                            () => _selectedRouteId = result.routes[i].id,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Selected: Route $selectedNumber',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${(selected.durationSeconds / 60).round()} min · '
                        '${selected.distanceMeters.round()} m · '
                        '${selected.shadeFraction == null ? 'Nighttime: shade estimate unavailable' : 'Shade comparison ready'}',
                      ),
                      if (result.timeZoneId != null)
                        Text(
                          'Estimate time zone: ${result.timeZoneId} '
                          '(saved sample).',
                        ),
                      const SizedBox(height: 12),
                      const Text('Route sketch (not a map)'),
                      const SizedBox(height: 4),
                      RouteSketch(
                        encodedRoutes: result.routes
                            .map((route) => route.encodedPolyline)
                            .toList(),
                        selectedIndex: selectedNumber - 1,
                      ),
                      const Text(
                        'Diagram spacing is stretched to show route differences. '
                        'It is not a street map or navigation.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Shade-data confidence: Prototype, not field-verified. '
                        'Building heights come from OSM tags or assumptions; '
                        'trees, construction, and terrain effects are not modeled.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Walking route data can miss sidewalks or paths. '
                        'Check real-world conditions before traveling.',
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteResult {
  const _RouteResult(
    this.routes,
    this.choices,
    this.destinationLabel,
    this.trip,
    this.timeZoneId,
  );

  final List<_RoutePreview> routes;
  final Map<String, dynamic> choices;
  final String destinationLabel;
  final ShadeRouteTrip trip;
  final String? timeZoneId;
}

class _RoutePreview {
  const _RoutePreview(
    this.id,
    this.durationSeconds,
    this.distanceMeters,
    this.shadeFraction,
    this.encodedPolyline,
  );

  factory _RoutePreview.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final duration = json['durationSeconds'];
    final distance = json['distanceMeters'];
    final shade = json['shadeFraction'];
    final geometry = json['encodedPolyline'];
    if (id is! String ||
        id.trim().isEmpty ||
        duration is! num ||
        !duration.isFinite ||
        duration <= 0 ||
        distance is! num ||
        !distance.isFinite ||
        distance <= 0 ||
        (shade != null &&
            (shade is! num || !shade.isFinite || shade < 0 || shade > 1)) ||
        geometry is! String ||
        geometry.isEmpty) {
      throw const FormatException('Invalid route fields');
    }
    return _RoutePreview(
      id,
      duration.toDouble(),
      distance.toDouble(),
      (shade as num?)?.toDouble(),
      geometry,
    );
  }

  final String id;
  final double durationSeconds;
  final double distanceMeters;
  final double? shadeFraction;
  final String encodedPolyline;
}

class _RouteChoiceCard extends StatelessWidget {
  const _RouteChoiceCard({
    required this.route,
    required this.number,
    required this.choices,
    required this.selected,
    required this.onTap,
  });

  final _RoutePreview route;
  final int number;
  final Map<String, dynamic> choices;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (choices['fastest'] == route.id) 'Fastest',
      if (choices['balanced'] == route.id) 'Balanced',
      if (choices['mostShade'] == route.id) 'Most shade',
    ];
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Route $number',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${(route.durationSeconds / 60).round()} min · '
                '${route.shadeFraction == null ? 'Nighttime' : 'Shade comparison ready'}',
              ),
              if (labels.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(labels.join(' · ')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
