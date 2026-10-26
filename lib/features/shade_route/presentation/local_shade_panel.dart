import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/coordinates.dart';
import '../services/local_shade_calculator.dart';

class LocalShadePanel extends StatefulWidget {
  const LocalShadePanel({super.key});
  @override
  State<LocalShadePanel> createState() => _LocalShadePanelState();
}

class _LocalShadePanelState extends State<LocalShadePanel> {
  LocalShadeBuildings? _buildings;
  final _routes = <({String name, WalkingGeometry geometry})>[];
  List<LocalShadeResult>? _results;
  String? _error;
  bool _levels = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final buildings = LocalShadeBuildings(
        jsonDecode(
          await rootBundle.loadString('data/buildings/pilot/buildings.json'),
        ) as Map<String, dynamic>,
      );
      final bundle = jsonDecode(
        await rootBundle.loadString('data/buildings/pilot/routes.json'),
      );
      if (bundle['schemaVersion'] != 1 || bundle['routes'] is! List) {
        throw const FormatException('Invalid route bundle.');
      }
      for (final r in bundle['routes']) {
        _routes.add((
          name: r['name'] as String,
          geometry: WalkingGeometry(
            points: (r['points'] as List)
                .map(
                  (p) => Coordinates(
                    latitude: (p['latitude'] as num).toDouble(),
                    longitude: (p['longitude'] as num).toDouble(),
                  ),
                )
                .toList(),
            durationSeconds: (r['durationSeconds'] as num).toDouble(),
            sourceUrl: r['sourceUrl'] as String,
            accessReviewed: r['accessReviewed'] == true,
          ),
        ));
      }
      if (mounted) setState(() => _buildings = buildings);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load reviewed shade data.');
      }
    }
  }

  void _calculate() {
    try {
      final results = _routes
          .map(
            (r) => const LocalShadeCalculator().calculate(
              r.geometry,
              _buildings!,
              DateTime.now(),
              allowLevelEstimates: _levels,
            ),
          )
          .toList();
      setState(() {
        _results = results;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _results = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Real route shade calculator',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_buildings == null && _error == null)
            const LinearProgressIndicator(),
          if (_buildings case final data?) ...[
            Text(
              '${data.buildings.length} mapped buildings in the Meadows-area extract',
            ),
            Text(
              '${data.explicitHeights} explicit heights · ${data.levelEstimates} floor-based estimates · ${data.unknownHeights} unknown heights',
            ),
            if (_routes.isEmpty)
              const Text(
                'Choose the exact public start and finish before adding a real walking route. Shade remains unknown until building heights are available.',
              ),
            if (_routes.isNotEmpty) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _levels,
                onChanged: (v) => setState(() {
                  _levels = v;
                  _results = null;
                }),
                title: const Text('Include floor-based height estimates'),
              ),
              FilledButton(
                onPressed: _calculate,
                child: const Text('Calculate building shade now'),
              ),
              if (_results case final results?)
                for (var i = 0; i < results.length; i++) ...[
                  Text(_routes[i].name),
                  Text(
                    _routes[i].geometry.accessReviewed
                        ? 'Pedestrian access reviewed'
                        : 'Candidate route: pedestrian access unverified',
                  ),
                  Text(
                    '${results[i].distanceMeters.round()} m · ${(_routes[i].geometry.durationSeconds / 60).round()} min provider estimate',
                  ),
                  Text(
                    results[i].modeledShadeFraction == null
                        ? 'Building shade unknown or no daylight'
                        : 'Local shade comparison ready',
                  ),
                  const Text(
                    'Remaining distance is unclassified; it is not proven to be sun-exposed.',
                  ),
                  if (results[i].cappedShadows)
                    const Text('Low sun: shadows beyond 250 m are excluded.'),
                ],
            ],
            ExpansionTile(
              title: const Text('Shade data and limitations'),
              children: [
                Text('Downloaded ${data.data['retrievedAt']}'),
                const Text('© OpenStreetMap contributors · ODbL'),
                const SelectableText('https://www.openstreetmap.org/copyright'),
                const Text(
                  'Footprints do not prove height or completeness. Trees, terrain and roof detail are not modeled. Building shade is an estimate, not a UV protection or temperature-reduction measurement. The calculator runs on this device without paid requests.',
                ),
              ],
            ),
          ],
          if (_error case final error?)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
