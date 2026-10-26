import 'cooling_photo_details.dart';

import 'package:flutter/material.dart';

import '../../../core/location/app_location.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/models/coordinates.dart';
import '../../heat_guard/presentation/weather_overview.dart';
import '../models/cooling_destination.dart';
import '../models/unofficial_cooling_directory.dart';
import '../services/cooling_actions.dart';
import '../../shade_route/services/city_trip_service.dart';

class UnofficialPlaceReport extends StatelessWidget {
  const UnofficialPlaceReport({
    super.key,
    required this.place,
    required this.directory,
    required this.actions,
    this.origin,
    this.discoveryMetadata,
    this.onDestinationSelected,
  });
  final Map<String, dynamic> place;
  final Map? discoveryMetadata;
  final UnofficialCoolingDirectory directory;
  final CoolingActions actions;
  final Coordinates? origin;
  final ValueChanged<CoolingDestination>? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final shared = LocationScope.maybeOf(context);
    final currentOrigin = shared == null ? origin : shared.position;
    final point = place['coordinates'] as Map;
    var canPlanRoute = true;
    try {
      CityTripService.validatePoint(
        CoolingDestination.fromStation(place).location,
      );
    } on FormatException {
      canPlanRoute = false;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(place['name'] as String),
        actions: const [CurrentTemperatureDisplay()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CoolingPhotoDetails(metadata: discoveryMetadata, actions: actions),
          Text(
            UnofficialCoolingDirectory.methodLabel(place),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(place['address'] as String),
          if (currentOrigin != null)
            Text(
              '${SettingsScope.distance(context, CoolingActions.distanceMeters(currentOrigin, point))} from your location · straight-line',
            ),
          const SizedBox(height: 12),
          Text(place['access'] as String),
          Text(place['hours'] as String? ?? 'Hours: see venue source.'),
          if (onDestinationSelected != null)
            FilledButton.icon(
              onPressed: canPlanRoute
                  ? () {
                      Navigator.pop(context);
                      onDestinationSelected!(
                        CoolingDestination.fromStation(place),
                      );
                    }
                  : null,
              icon: const Icon(Icons.route),
              label: Text(
                canPlanRoute
                    ? 'Plan a route here'
                    : 'Outside route planning area',
              ),
            ),
          if (place['phone'] != null)
            TextButton.icon(
              onPressed: () =>
                  _open(context, () => actions.dial(place['phone'] as String)),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Call venue'),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Sources & map details'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Reviewed ${(place['evidence'] as Map)['reviewedOn'] ?? directory.data['checkedOn']}",
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(point['precision'] as String),
              ),
              for (final id in place['sourceIds'] as List)
                TextButton.icon(
                  onPressed: () => _open(
                    context,
                    () => actions.openSource(
                      directory.source(id as String)['url'] as String,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(directory.source(id)['title'] as String),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    var ok = false;
    try {
      ok = await action();
    } catch (_) {
      // show the link error below
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this link. Please try again.'),
        ),
      );
    }
  }
}
