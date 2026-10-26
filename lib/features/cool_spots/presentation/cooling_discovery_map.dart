import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/coordinates.dart';
import '../../shade_route/presentation/shade_street_map.dart';

class CoolingDiscoveryMap extends StatefulWidget {
  const CoolingDiscoveryMap({
    super.key,
    required this.places,
    required this.onSelected,
    required this.tilesEnabled,
    this.origin,
  });
  final List<Map<String, dynamic>> places;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final bool tilesEnabled;
  final Coordinates? origin;

  @override
  State<CoolingDiscoveryMap> createState() => _CoolingDiscoveryMapState();
}

class _CoolingDiscoveryMapState extends State<CoolingDiscoveryMap> {
  final _controller = MapController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final located = widget.places
        .where((p) => p['coordinates'] != null)
        .toList();
    LatLng point(Map<String, dynamic> place) {
      final coordinates = place['coordinates'] as Map;
      return LatLng(
        (coordinates['latitude'] as num).toDouble(),
        (coordinates['longitude'] as num).toDouble(),
      );
    }

    if (located.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No verified map points for these results.')),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 300,
        child: ShadeStreetMap(
          controller: _controller,
          routes: const [],
          selectedIndex: 0,
          origin: widget.origin,
          active: ModalRoute.of(context)?.isCurrent ?? true,
          tilesEnabled: widget.tilesEnabled,
          onRouteSelected: (_) {},
          onPointSelected: (_) {},
          onReady: () {
            final points = located.map(point).toList();
            if (widget.origin case final origin?) {
              points.add(LatLng(origin.latitude, origin.longitude));
            }
            if (points.length == 1) {
              _controller.move(points.single, 14);
            } else {
              _controller.fitCamera(
                CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(points),
                  padding: const EdgeInsets.all(40),
                  maxZoom: 15,
                ),
              );
            }
          },
          placeMarkers: [
            for (final place in located)
              Marker(
                point: point(place),
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: place['name'] as String,
                  onPressed: () => widget.onSelected(place),
                  icon: Icon(
                    Icons.location_on,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
