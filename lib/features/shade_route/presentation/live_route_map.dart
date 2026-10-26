import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_sketch.dart';

class LiveRouteMap extends StatelessWidget {
  const LiveRouteMap({
    required this.encodedRoutes,
    required this.selectedIndex,
    super.key,
  });

  final List<String> encodedRoutes;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (encodedRoutes.isEmpty ||
        selectedIndex < 0 ||
        selectedIndex >= encodedRoutes.length) {
      throw const FormatException('No selected walking route');
    }
    final paths = encodedRoutes
        .map(
          (encoded) =>
              decodeRoutePolyline(encoded)
                  .map((point) => LatLng(point.dy, point.dx))
                  .toList(),
        )
        .toList();
    final selected = paths[selectedIndex];
    final all = paths.expand((path) => path).toList();
    final south = all
        .map((point) => point.latitude)
        .reduce((a, b) => a < b ? a : b);
    final north = all
        .map((point) => point.latitude)
        .reduce((a, b) => a > b ? a : b);
    final west = all
        .map((point) => point.longitude)
        .reduce((a, b) => a < b ? a : b);
    final east = all
        .map((point) => point.longitude)
        .reduce((a, b) => a > b ? a : b);
    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
    return SizedBox(
      height: 280,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: selected.first, zoom: 15),
        onMapCreated: (controller) =>
            controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 32)),
        myLocationEnabled: false,
        markers: {
          Marker(markerId: const MarkerId('start'), position: selected.first),
          Marker(
            markerId: const MarkerId('destination'),
            position: selected.last,
          ),
        },
        polylines: {
          for (var i = 0; i < paths.length; i++)
            Polyline(
              polylineId: PolylineId('route-$i'),
              points: paths[i],
              color: i == selectedIndex
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              width: i == selectedIndex ? 6 : 3,
            ),
        },
      ),
    );
  }
}
