import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/feature_header.dart';
import '../models/cool_spots_contract.dart';
import '../services/cool_spots_service.dart';
import 'official_cooling_page.dart';
import '../models/cooling_destination.dart';

typedef CoolSpotsLoader = Future<Map<String, dynamic>> Function();

class CoolSpotsPage extends StatefulWidget {
  const CoolSpotsPage({
    super.key,
    this.dataLoader,
    this.service = const CoolSpotsService(),
    this.onDestinationSelected,
    this.mapTilesEnabled = true,
  });

  final bool mapTilesEnabled;
  final CoolSpotsLoader? dataLoader;
  final CoolSpotsService service;
  final ValueChanged<CoolingDestination>? onDestinationSelected;

  @override
  State<CoolSpotsPage> createState() => _CoolSpotsPageState();
}

class _CoolSpotsPageState extends State<CoolSpotsPage> {
  late Future<Map<String, dynamic>> _data = _loadData();
  Map<String, dynamic>? _localExample;
  bool _loadingFunction = false;
  bool _functionFailed = false;
  Map<String, dynamic>? _localCenters;
  bool _loadingCenters = false;
  bool _centersFailed = false;
  bool _showDetailedReport = false;

  Future<void> _loadLocalCenters() async {
    setState(() {
      _loadingCenters = true;
      _centersFailed = false;
    });
    try {
      final response = await widget.service.getLocalCenters();
      if (!mounted) return;
      setState(() => _localCenters = response);
    } catch (_) {
      if (!mounted) return;
      setState(() => _centersFailed = true);
    } finally {
      if (mounted) setState(() => _loadingCenters = false);
    }
  }

  Future<void> _loadLocalExample(Map<String, dynamic> origin) async {
    setState(() {
      _loadingFunction = true;
      _functionFailed = false;
      _localExample = null;
    });
    try {
      final example = await widget.service.getLocalExample(origin);
      if (!mounted) return;
      setState(() => _localExample = example);
    } catch (_) {
      if (!mounted) return;
      setState(() => _functionFailed = true);
    } finally {
      if (mounted) setState(() => _loadingFunction = false);
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    if (widget.dataLoader != null) {
      final data = await widget.dataLoader!();
      CoolSpotsContract.dataset(data['dataset']);
      CoolSpotsContract.fictionalPlaces(data['example']);
      return data;
    }
    final texts = await Future.wait([
      rootBundle.loadString('data/cooling_centers/clark_county_june_2026.json'),
      rootBundle.loadString('assets/cool_spots_demo.json'),
    ]);
    final dataset = CoolSpotsContract.dataset(jsonDecode(texts[0]));
    final example = CoolSpotsContract.fictionalPlaces(jsonDecode(texts[1]));
    return {'dataset': dataset, 'example': example};
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dataLoader == null) {
      return OfficialCoolingPage(
        mapTilesEnabled: widget.mapTilesEnabled,
        onDestinationSelected: widget.onDestinationSelected,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const FeatureHeader(
          icon: Icons.ac_unit,
          title: 'Cool Spots',
          description: 'Find places to cool down near your route.',
        ),
        const SizedBox(height: 16),
        const Text('No live cooling spot search is connected.'),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saved place records could not be loaded.'),
                      TextButton(
                        onPressed: () => setState(() {
                          _data = _loadData();
                        }),
                        child: const Text('Retry saved records'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Column(
                children: [
                  LinearProgressIndicator(
                    semanticsLabel: 'Loading saved Cool Spots records',
                  ),
                  Text('Loading saved places…'),
                ],
              );
            }
            final data = snapshot.data!;
            final dataset = _localCenters?['dataset'] ?? data['dataset'];
            final example = data['example'];
            if (dataset is! Map<String, dynamic> ||
                example is! Map<String, dynamic> ||
                example['sampleOnly'] != true ||
                dataset['centers'] is! List ||
                dataset['sampleReference'] is! Map ||
                example['indoorPlaces'] is! List) {
              return const Text('Saved place records are incomplete.');
            }
            final reference =
                dataset['sampleReference'] as Map<String, dynamic>;
            final origin = reference['location'] as Map<String, dynamic>;
            final centers = (dataset['centers'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
            final businesses = (example['indoorPlaces'] as List<dynamic>)
                .cast<Map<String, dynamic>>();

            final safePastDay = DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 1))
                .toIso8601String()
                .substring(0, 10);
            final exactStatuses = _localCenters?['dateStatuses'] as Map?;
            bool expired(Map<String, dynamic> center) => exactStatuses == null
                ? (center['validUntil'] as String).compareTo(safePastDay) < 0
                : exactStatuses[center['id']] == 'expired';
            final past = centers.where(expired).toList();
            final listed = centers.where((center) => !expired(center)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cooling spot status',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text('No open cooling center is verified.'),
                        Text(
                          '${past.length} past county listings · '
                          '${businesses.length} fictional indoor example${businesses.length == 1 ? '' : 's'}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(
                    () => _showDetailedReport = !_showDetailedReport,
                  ),
                  icon: Icon(
                    _showDetailedReport
                        ? Icons.expand_less
                        : Icons.article_outlined,
                  ),
                  label: Text(
                    _showDetailedReport
                        ? 'Hide detailed report'
                        : 'View detailed report',
                  ),
                ),
                if (_showDetailedReport) ...[
                  if (kDebugMode) ...[
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
                              'Load a fictional indoor place through the local '
                              'Functions emulator. This uses a saved example '
                              'point, not your location or a live Places search.',
                            ),
                            TextButton(
                              onPressed: _loadingFunction
                                  ? null
                                  : () => _loadLocalExample(origin),
                              child: const Text(
                                'Load local Cool Spots example',
                              ),
                            ),
                            if (_loadingFunction)
                              const LinearProgressIndicator(
                                semanticsLabel:
                                    'Loading local Cool Spots example',
                              ),
                            if (_functionFailed)
                              const Text(
                                'Local Function unavailable. Start the Firebase '
                                'Functions emulator, then retry.',
                              ),
                            if (_localExample != null) ...[
                              const Text(
                                'Local Function responded with a fictional '
                                'historical business example. No Places API '
                                'request was made.',
                              ),
                              for (final business
                                  in (_localExample!['indoorPlaces']
                                          as List<dynamic>)
                                      .cast<Map<String, dynamic>>())
                                _BusinessCard(
                                  business: business,
                                  origin: origin,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Official cooling centers',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (kDebugMode) ...[
                            TextButton(
                              onPressed: _loadingCenters
                                  ? null
                                  : _loadLocalCenters,
                              child: const Text('Read local center records'),
                            ),
                            if (_loadingCenters)
                              const LinearProgressIndicator(
                                semanticsLabel: 'Reading local center records',
                              ),
                            if (_centersFailed)
                              const Text(
                                'Local center records unavailable. Start and '
                                'seed the Firestore emulator, then retry.',
                              ),
                            if (_localCenters != null)
                              Text(
                                'Showing ${centers.length} county records from '
                                'the local Firestore emulator. Source-local date: '
                                '${_localCenters!['localDate']}.',
                              )
                            else
                              const Text(
                                'Showing saved county records bundled with the app.',
                              ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            listed.isEmpty
                                ? 'No current cooling-station activation is verified '
                                      'in this saved dataset.'
                                : 'Some saved dates have not safely expired. '
                                      'Opening is not verified; check the county '
                                      'source before visiting.',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'County source checked against its website on '
                            '${_shortDate(dataset['sourceCheckedAt'] as String)}. '
                            'This was a record check, not a site visit.',
                          ),
                          Text(
                            'Distances below are approximate straight-line '
                            'distances from a fixed Las Vegas example '
                            'point, not from your phone or a walking route.',
                          ),
                          if (centers.isEmpty)
                            const Text(
                              'No official records in this saved source.',
                            ),
                          for (final center in listed)
                            _CenterCard(
                              center: center,
                              origin: origin,
                              archived: false,
                            ),
                          if (past.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Past official listings — inactive',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Text(
                              'These activation dates ended. Do not '
                              'travel based on these old listings.',
                            ),
                            for (final center in past)
                              _CenterCard(
                                center: center,
                                origin: origin,
                                archived: true,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nearby indoor places',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No live business results loaded. '
                            'A cafe or restaurant is not an official cooling '
                            'center; air conditioning is not verified.',
                          ),
                          if (_localExample != null)
                            const Text(
                              'The fictional business from the local Function '
                              'is shown above.',
                            )
                          else if (businesses.isEmpty)
                            const Text(
                              'No indoor business examples available.',
                            ),
                          if (_localExample == null)
                            for (final business in businesses)
                              _BusinessCard(business: business, origin: origin),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.center,
    required this.origin,
    required this.archived,
  });

  final Map<String, dynamic> center;
  final Map<String, dynamic> origin;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final location = center['location'] as Map<String, dynamic>;
    final distance = _distanceMeters(origin, location).round();
    return Semantics(
      label: archived
          ? 'Past official cooling-station listing'
          : 'Official cooling-station listing, opening not checked live',
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                archived
                    ? 'PAST COUNTY LISTING · INACTIVE'
                    : 'COUNTY COOLING-STATION LISTING',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                center['name'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(center['address'] as String),
              Text('Approx. $distance m straight-line from example point'),
              Text('Listed hours: ${center['hours']}'),
              Text(
                'Activation: ${center['validFrom']} to '
                '${center['validUntil']}',
              ),
              Text(
                'Record checked: '
                '${_shortDate(center['lastVerifiedAt'] as String)}',
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: center['sourceUrl'] as String),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('County source link copied'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy county source link'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business, required this.origin});

  final Map<String, dynamic> business;
  final Map<String, dynamic> origin;

  @override
  Widget build(BuildContext context) {
    final location = business['location'] as Map<String, dynamic>;
    final distance = _distanceMeters(origin, location).round();
    return Semantics(
      label: 'Fictional indoor business example, not a cooling center',
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FICTIONAL INDOOR BUSINESS EXAMPLE',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                business['name'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Approx. $distance m straight-line from example point'),
              const Text(
                'Opening status unknown · Cooling facilities '
                'not verified',
              ),
              const Text('Do not travel to this invented example.'),
            ],
          ),
        ),
      ),
    );
  }
}

String _shortDate(String iso) {
  final date = DateTime.parse(iso).toLocal();
  return '${date.month}/${date.day}/${date.year}';
}

double _distanceMeters(Map<String, dynamic> a, Map<String, dynamic> b) {
  const earthRadius = 6371000.0;
  final lat1 = (a['latitude'] as num).toDouble() * math.pi / 180;
  final lat2 = (b['latitude'] as num).toDouble() * math.pi / 180;
  final deltaLat = lat2 - lat1;
  final deltaLon =
      ((b['longitude'] as num).toDouble() -
          (a['longitude'] as num).toDouble()) *
      math.pi /
      180;
  final h =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLon / 2), 2);
  return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}
