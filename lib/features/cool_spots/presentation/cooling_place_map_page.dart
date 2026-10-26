import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/app_location.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/models/coordinates.dart';
import '../../heat_guard/presentation/weather_overview.dart';
import '../../shade_route/presentation/shade_street_map.dart';
import '../../shade_route/services/city_trip_service.dart';
import '../models/cooling_destination.dart';
import '../models/unofficial_cooling_directory.dart';
import '../services/cooling_actions.dart';

class CoolingPlaceMapPage extends StatefulWidget {
  const CoolingPlaceMapPage({
    super.key,
    required this.place,
    required this.official,
    required this.onDetails,
    this.origin,
    this.tilesEnabled = true,
    this.onDestinationSelected,
  });

  final Map<String, dynamic> place;
  final bool official, tilesEnabled;
  final Coordinates? origin;
  final ValueChanged<BuildContext> onDetails;
  final ValueChanged<CoolingDestination>? onDestinationSelected;

  @override
  State<CoolingPlaceMapPage> createState() => _CoolingPlaceMapPageState();
}

class _CoolingPlaceMapPageState extends State<CoolingPlaceMapPage> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shared = LocationScope.maybeOf(context);
    final origin = shared == null ? widget.origin : shared.position;
    final point = widget.place['coordinates'] as Map?;
    final destination = point == null
        ? null
        : Coordinates(
            latitude: (point['latitude'] as num).toDouble(),
            longitude: (point['longitude'] as num).toDouble(),
          );
    var supported = destination != null;
    if (destination != null) {
      try {
        CityTripService.validatePoint(destination);
      } on FormatException {
        supported = false;
      }
    }
    final name = widget.place['name'] as String;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          const CurrentTemperatureDisplay(compact: true),
          IconButton(
            tooltip: 'Place details',
            icon: const Icon(Icons.more_vert),
            onPressed: () => widget.onDetails(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            if (destination != null)
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .43).clamp(
                  220.0,
                  400.0,
                ),
                child: ShadeStreetMap(
                  controller: _map,
                  routes: const [],
                  selectedIndex: 0,
                  origin: origin,
                  destination: destination,
                  active: ModalRoute.of(context)?.isCurrent ?? true,
                  tilesEnabled: widget.tilesEnabled,
                  onReady: () => _map.move(
                    LatLng(destination.latitude, destination.longitude),
                    15.5,
                  ),
                  onRouteSelected: (_) {},
                  onPointSelected: (_) {},
                ),
              )
            else
              const SizedBox(
                height: 150,
                child: Center(child: Text('No published map point')),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    widget.official
                        ? 'Official cooling location'
                        : UnofficialCoolingDirectory.methodLabel(widget.place),
                  ),
                  const SizedBox(height: 6),
                  Text(widget.place['address'] as String),
                  if (origin != null && point != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${SettingsScope.distance(context, CoolingActions.distanceMeters(origin, point))} away · straight-line',
                    ),
                  ],
                  if (!widget.official) ...[
                    const SizedBox(height: 6),
                    Text(widget.place['access'] as String),
                  ],
                  if (shared != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      shared.status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (widget.onDestinationSelected != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('cooling-map-destination'),
                        onPressed: supported && shared?.busy != true
                            ? () {
                                final selection =
                                    CoolingDestination.fromStation(
                                      widget.place,
                                      startFromCurrentLocation: true,
                                    );
                                Navigator.pop(context);
                                widget.onDestinationSelected!(selection);
                              }
                            : null,
                        icon: const Icon(Icons.route),
                        label: Text(
                          !supported
                              ? 'Outside route planning area'
                              : shared?.busy == true
                              ? 'Getting location…'
                              : origin != null
                              ? 'Route from my location'
                              : 'Set destination',
                        ),
                      ),
                    ),
                  if (supported && origin == null && shared?.busy != true)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Choose your starting point in Shade Route.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
