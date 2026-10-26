import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BuildingDataStatus extends StatefulWidget {
  const BuildingDataStatus({super.key});

  @override
  State<BuildingDataStatus> createState() => _BuildingDataStatusState();
}

class _BuildingDataStatusState extends State<BuildingDataStatus> {
  late final Future<Map<String, dynamic>> _manifest = _loadManifest();

  Future<Map<String, dynamic>> _loadManifest() async {
    final text = await rootBundle.loadString('assets/building_manifest.json');
    return jsonDecode(text) as Map<String, dynamic>;
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
              'Real building data prepared',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, dynamic>>(
              future: _manifest,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Building data summary is unavailable.');
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                final data = snapshot.data!;
                final count = data['buildingCount'] as int;
                final confidence =
                    data['heightConfidenceCounts'] as Map<String, dynamic>;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count OpenStreetMap building footprints are stored '
                      'locally for the Las Vegas example area.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Height sources: ${confidence['high']} explicit tags, '
                      '${confidence['medium']} estimated from levels, '
                      '${confidence['low']} assumed.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The demo above uses buildings from this saved extract. '
                      'Its route lines are invented, not verified walking '
                      'paths. Missing demo heights use an assumed 9 m; city routes use the separate Las Vegas shade dataset.',
                    ),
                    const SizedBox(height: 8),
                    const Text('© OpenStreetMap contributors · ODbL'),
                    const SelectableText(
                      'https://www.openstreetmap.org/copyright',
                    ),
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
