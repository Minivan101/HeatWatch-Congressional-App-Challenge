import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/coordinates.dart';
import '../services/city_trip_service.dart';

class ShadeStreetMap extends StatefulWidget {
  const ShadeStreetMap({
    super.key,
    required this.controller,
    required this.routes,
    required this.selectedIndex,
    required this.onRouteSelected,
    required this.onPointSelected,
    required this.onReady,
    this.shadeSegments = const [],
    this.placeMarkers = const [],
    this.userPosition,
    this.userHeading = 0,
    this.onUserGesture,
    this.origin,
    this.destination,
    this.active = true,
    this.tilesEnabled = true,
  });
  final List<Marker> placeMarkers;
  final List<Map<String, dynamic>> shadeSegments;
  final MapController controller;
  final List<CityWalkingRoute> routes;
  final int selectedIndex;
  final ValueChanged<int> onRouteSelected;
  final ValueChanged<Coordinates> onPointSelected;
  final VoidCallback onReady;
  final Coordinates? origin, destination, userPosition;
  final double userHeading;
  final VoidCallback? onUserGesture;
  final bool active, tilesEnabled;
  @override
  State<ShadeStreetMap> createState() => _ShadeStreetMapState();
}

class _ShadeStreetMapState extends State<ShadeStreetMap>
    with WidgetsBindingObserver {
  final LayerHitNotifier<int> _hits = ValueNotifier(null);
  bool _tileError = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  int _tileVersion = 0;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hits.dispose();
    super.dispose();
  }

  LatLng _latLng(Coordinates p) => LatLng(p.latitude, p.longitude);
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selectedIndex;
    final origin = widget.origin;
    final localOrigin =
        origin != null && CityTripService.isInPlanningArea(origin);
    final order = [
      for (var i = 0; i < widget.routes.length; i++)
        if (i != selected) i,
      if (widget.routes.isNotEmpty) selected,
    ];
    return Stack(
      children: [
        FlutterMap(
          key: const ValueKey('shade-street-map'),
          mapController: widget.controller,
          options: MapOptions(
            initialCenter: _latLng(
              localOrigin ? origin : CityTripService.planningCenter,
            ),
            initialZoom: localOrigin ? 14 : 12,
            minZoom: 3,
            maxZoom: 19,
            onMapReady: widget.onReady,
            onPositionChanged: (_, gesture) {
              if (gesture) widget.onUserGesture?.call();
            },
            onTap: (_, p) => widget.onPointSelected(
              Coordinates(latitude: p.latitude, longitude: p.longitude),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            if (widget.active && widget.tilesEnabled && _foreground)
              _StreetTiles(
                key: ValueKey('osm-tiles-$_tileVersion'),
                onError: () {
                  if (_tileError) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_tileError) {
                      setState(() => _tileError = true);
                    }
                  });
                },
              ),
            GestureDetector(
              onTap: () {
                final values = _hits.value?.hitValues;
                if (values != null && values.isNotEmpty) {
                  widget.onRouteSelected(values.first);
                }
              },
              child: PolylineLayer<int>(
                hitNotifier: _hits,
                minimumHitbox: 20,
                polylines: [
                  for (final i in order)
                    Polyline<int>(
                      points: widget.routes[i].geometry.points
                          .map(_latLng)
                          .toList(),
                      hitValue: i,
                      color: i == selected
                          ? colors.primary
                          : const Color(0xff8fadb9),
                      strokeWidth: i == selected ? 6 : 4,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                ],
              ),
            ),

            if (widget.shadeSegments.isNotEmpty)
              IgnorePointer(
                child: PolylineLayer(
                  polylines: [
                    for (final segment in widget.shadeSegments)
                      Polyline(
                        points: (segment['points'] as List)
                            .map(
                              (p) => LatLng(
                                (p[0] as num).toDouble(),
                                (p[1] as num).toDouble(),
                              ),
                            )
                            .toList(),
                        strokeWidth: 6,
                        color: switch (segment['kind']) {
                          'building' => const Color(0xff1565c0),
                          'canopy' => const Color(0xff2e7d32),
                          'open' => const Color(0xffef8c00),
                          _ => const Color(0xff757575),
                        },
                      ),
                  ],
                ),
              ),
            MarkerLayer(
              markers: [
                ...widget.placeMarkers,
                if (widget.userPosition case final p?)
                  Marker(
                    point: _latLng(p),
                    width: 42,
                    height: 42,
                    rotate: false,
                    child: Semantics(
                      label: 'Your live location',
                      child: Transform.rotate(
                        angle: widget.userHeading * 3.141592653589793 / 180,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.origin case final p?)
                  Marker(
                    point: _latLng(p),
                    width: 44,
                    height: 44,
                    child: Semantics(
                      label: 'Starting point',
                      child: const Icon(
                        Icons.radio_button_checked,
                        color: Color(0xff1565c0),
                        size: 28,
                      ),
                    ),
                  ),
                if (widget.destination case final p?)
                  Marker(
                    point: _latLng(p),
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      label: 'Destination pin',
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xffc62828),
                        size: 42,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        Positioned(
          right: 8,
          top: 4,
          child: Material(
            color: colors.surface.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        if (_tileError)
          Positioned(
            left: 12,
            right: 12,
            top: 212,
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Street map unavailable. Your selected points and routes remain.',
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _tileError = false;
                        _tileVersion++;
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StreetTiles extends StatefulWidget {
  const _StreetTiles({super.key, required this.onError});
  final VoidCallback onError;
  @override
  State<_StreetTiles> createState() => _StreetTilesState();
}

class _StreetTilesState extends State<_StreetTiles> {
  late final _provider = NetworkTileProvider(
    cachingProvider: kIsWeb
        ? null
        : BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 128000000,
          ),
  );
  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: const String.fromEnvironment(
      'HEATWATCH_MAP_TILES',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    userAgentPackageName: 'com.ivantrac.heatwatch',
    tileProvider: _provider,
    maxNativeZoom: 19,
    panBuffer: 0,
    keepBuffer: 2,
    errorTileCallback: (_, _, _) => widget.onError(),
  );
}
