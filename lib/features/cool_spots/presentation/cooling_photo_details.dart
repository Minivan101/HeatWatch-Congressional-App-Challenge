import 'package:flutter/material.dart';

import '../services/cooling_actions.dart';

class CoolingPhotoDetails extends StatelessWidget {
  const CoolingPhotoDetails({super.key, this.metadata, required this.actions});
  final Map? metadata;
  final CoolingActions actions;
  @override
  Widget build(BuildContext context) {
    if (metadata == null) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Photo & amenity evidence'),
      children: [
        if (metadata!['retrievedOn'] is String)
          Text('Photo retrieved ${metadata!['retrievedOn']}'),
        if (metadata!['photoCredit'] is String)
          Text('Photo: ${metadata!['photoCredit']}'),
        if (metadata!['photoLicense'] is String)
          Text(metadata!['photoLicense'] as String),
        if (metadata!['modifications'] is String)
          Text(metadata!['modifications'] as String),
        for (final entry in {
          'Photo source': metadata!['photoSource'],
          'Photo license': metadata!['photoLicenseUrl'],
          'Amenity source': metadata!['amenitySource'],
          if (metadata!['amenitySources'] is Map)
            for (final evidence in (metadata!['amenitySources'] as Map).entries)
              '${evidence.key} evidence': evidence.value,
        }.entries)
          if (entry.value is String)
            TextButton(
              onPressed: () async {
                final opened = await actions.openSource(entry.value as String);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open source. Try again.'),
                    ),
                  );
                }
              },
              child: Text(entry.key),
            ),
      ],
    );
  }
}
