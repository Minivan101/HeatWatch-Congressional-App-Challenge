import 'dart:async';

import '../../../core/saved_places/place_search_sheet.dart';
import '../../../core/saved_places/saved_places.dart';
import '../../../core/saved_places/saved_places_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/coordinates.dart';
import '../../../core/settings/app_settings.dart';
import '../services/navigation_refresh_policy.dart';
import '../services/walking_corridor_selection.dart';
import '../services/route_preference_selector.dart';
import '../services/route_similarity.dart';
import '../../../core/location/app_location.dart';
import '../../cool_spots/models/cooling_destination.dart';
import '../../heat_guard/models/free_weather.dart';
import '../../heat_guard/services/weather_repository.dart';
import '../services/city_trip_service.dart';
import '../services/local_shade_calculator.dart';
import '../services/route_shade_repository.dart';
import '../services/route_weather_policy.dart';
import 'shade_street_map.dart';
import '../services/pedestrian_trip_service.dart';
import '../services/walking_navigation.dart';

class CityTripPanel extends StatefulWidget {
  const CityTripPanel({
    super.key,
    this.destination,
    required this.weather,
    this.active = true,
    this.onCoolingDirectory,
    this.onDestinationSelected,
    this.onClearDestination,
    this.service,
    this.shadeCalculator,
    this.tilesEnabled = true,
    this.now,
  });
  final DateTime Function()? now;
  final CoolingDestination? destination;
  final WeatherRepository weather;
  final bool active, tilesEnabled;
  final VoidCallback? onCoolingDirectory, onClearDestination;
  final ValueChanged<CoolingDestination>? onDestinationSelected;
  final CityTripService? service;
  final Future<Map<String, dynamic>> Function(CityWalkingRoute, DateTime)?
  shadeCalculator;
  @override
  State<CityTripPanel> createState() => _CityTripPanelState();
}

class _CityTripPanelState extends State<CityTripPanel> {
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  late final _service = widget.service ?? PedestrianTripService();
  final _shadeData = RouteShadeRepository();
  AppLocation? _location;
  bool _navigating = false, _following = true, _rerouting = false;
  bool _manualSelection = false;
  WalkingProgress? _progress;
  final _routeTracker = WalkingRouteTracker();
  Coordinates? _lastNavigationPoint;
  DateTime? _lastFixAt, _offRouteSince, _lastNavigationFixAt;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  double _heading = 0;
  Timer? _gpsWatchdog;
  bool _gpsStale = false, _navigationError = false;
  Coordinates? _routeOrigin;
  List<Coordinates>? _remainingVia;
  DateTime? _lastComparison;
  final _refreshPolicy = const NavigationRefreshPolicy();

  void _stopNavigation() {
    _token++;
    _busy = false;
    _location?.stopTracking();
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _navigating = false;
    _progress = null;
    _routeTracker.reset();
    _lastNavigationPoint = null;
    _lastFixAt = null;
    _offRouteSince = null;
    _lastNavigationFixAt = null;
    _gpsStale = false;
    _rerouting = false;
    _navigationError = false;
  }

  Future<void> _startNavigation() async {
    final location = _location;
    if (_busy || _navigating) return;
    if (_route == null ||
        location == null ||
        location.position == null ||
        !location.locationAllowed) {
      setState(
        () =>
            _error = 'Enable location in Settings to start walking navigation.',
      );
      return;
    }
    try {
      _remainingVia ??= _parseVia();
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString());
      return;
    }
    setState(() {
      _start = null;
      _departure = _now();
      _navigating = true;
      _following = true;
      _error = null;
    });
    final token = _token;
    location.startTracking();
    _gpsWatchdog?.cancel();
    _gpsWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_navigating) return;
      final at = _location?.fix?.at;
      final stale = !_refreshPolicy.isFresh(at, _now());
      if (stale != _gpsStale) setState(() => _gpsStale = stale);
      if (_refreshPolicy.shouldRefresh(
        now: _now(),
        lastComparison: _lastComparison,
        fixAt: at,
        busy: _busy,
        offRouteMeters: _progress?.offRouteMeters ?? double.infinity,
      )) {
        _lastComparison = _now();
        unawaited(_calculate(navigation: true));
      }
    });
    if (_drawer.isAttached) {
      await _drawer.animateTo(
        .28,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    if (!mounted || !_navigating || token != _token) return;

    final route = _route;
    final p = location.position;
    if (route == null ||
        p == null ||
        !location.locationAllowed ||
        location.error != null) {
      setState(() {
        _stopNavigation();
        _error =
            location.error ??
            'Location unavailable. Choose a start or enable it in Settings.';
      });
      return;
    }

    final initialProgress = walkingProgress(route, p);
    if (initialProgress.offRouteMeters > 25 ||
        initialProgress.alongMeters > 25) {
      await _calculate(navigation: true);
    } else {
      await _recalculateShades();
      if (mounted && _navigating) _updateNavigation();
    }
  }

  void _updateNavigation() {
    if (!_navigating || _route == null) return;
    final location = _location;
    if (location?.locationAllowed != true ||
        location?.position == null ||
        location?.error != null) {
      setState(() {
        _stopNavigation();
        _error = location?.error ?? 'Location is off. Navigation stopped.';
      });
      return;
    }
    final fix = location!.fix;
    if (!_refreshPolicy.isFresh(fix?.at, _now())) {
      if (!_gpsStale) setState(() => _gpsStale = true);
      return;
    }
    if (fix == null || fix.at == _lastFixAt) return;
    final recovered = _gpsStale;
    final previousFix = _lastNavigationFixAt;
    _lastNavigationFixAt = fix.at;
    final point = fix.point;
    final progress = _routeTracker.update(_route!, point);
    if (progress.offRouteMeters <= 20 && _remainingVia?.isNotEmpty == true) {
      final offsets = walkingWaypointOffsets(_route!, _remainingVia!);
      var passed = 0;
      while (passed < offsets.length &&
          progress.alongMeters + 8 >= offsets[passed]) {
        passed++;
      }
      if (passed > 0) _remainingVia = _remainingVia!.skip(passed).toList();
    }
    if (fix.heading != null && fix.speed >= .5) {
      _heading = fix.heading!;
    } else if (_lastNavigationPoint != null &&
        walkingDistance(_lastNavigationPoint!, point) >= 3) {
      _heading = walkingBearing(_lastNavigationPoint!, point);
    } else if (_lastNavigationPoint == null) {
      _heading = progress.bearing;
    }
    _lastFixAt = fix.at;
    _lastNavigationPoint = point;
    setState(() {
      _progress = progress;
      _gpsStale = false;
    });
    if (_following && _mapReady && widget.active) {
      _map.moveAndRotate(
        LatLng(point.latitude, point.longitude),
        17,
        -_heading,
      );
    }

    if (progress.offRouteMeters > 35) {
      _offRouteSince ??= fix.at;
      if (fix.at.difference(_offRouteSince!) >= const Duration(seconds: 5) &&
          fix.at.difference(_lastReroute) >= const Duration(seconds: 20) &&
          !_busy) {
        _lastReroute = fix.at;
        unawaited(_calculate(navigation: true));
      }
    } else {
      _offRouteSince = null;
    }
    if (recovered &&
        !_busy &&
        !progress.arrived &&
        _refreshPolicy.shouldRefreshAfterGap(
          now: _now(),
          lastComparison: _lastComparison,
          previousFix: previousFix,
          fixAt: fix.at,
        )) {
      _lastComparison = _now();
      unawaited(_calculate(navigation: true));
    }
    if (progress.arrived) {
      setState(() {
        _stopNavigation();
        _progress = progress;
      });
    }
  }

  final _map = MapController();
  final _drawer = DraggableScrollableController();
  final _startText = TextEditingController(),
      _endText = TextEditingController(),
      _viaText = TextEditingController();
  CityPlace? _start, _end;
  List<CityWalkingRoute> _routes = [];
  List<Map<String, dynamic>?> _shades = [];
  int _selected = 0, _token = 0;
  bool _busy = false, _mapReady = false;
  WeatherReading? _routeWeather;
  bool? _mapTarget;
  String? _error;
  late DateTime _departure;
  double? _originLat, _originLon;
  AppSettings? _settings;
  RoutePreference _preference = RoutePreference.mostShade;
  final _overlap = RouteOverlapComparison();

  List<RoutePreferenceMetric> get _metrics => [
    for (var i = 0; i < _routes.length; i++)
      RoutePreferenceMetric(
        _duration(_routes[i]),
        shade: (_shades[i]?['shade'] as num?)?.toDouble(),
        coverage: (_shades[i]?['coverage'] as num?)?.toDouble(),
        daylight: _daylightFraction(_shades[i]),
        timeTotals: _shades[i]?['timeTotals'] as Map?,
      ),
  ];
  bool get _cloudyDeparture => cloudsMakeShadeComparisonIrrelevant(
    routeConditionAt(_routeWeather, _departure, _now()),
  );
  RoutePreferenceSelection _choiceFor(RoutePreference preference) =>
      selectPreferredRoute(
        _cloudyDeparture ? RoutePreference.fastest : preference,
        _metrics,
      );
  bool get _singleChoice {
    if (_routes.isEmpty) return false;
    final fastest = _choiceFor(RoutePreference.fastest).index;
    final shade = _choiceFor(RoutePreference.mostShade).index;
    return fastest == shade ||
        _overlap.matches(_routes[fastest], _routes[shade]);
  }

  RoutePreferenceSelection get _recommendation =>
      _choiceFor(_singleChoice ? RoutePreference.fastest : _preference);

  Future<void> _refreshRouteWeather(Coordinates origin, int token) async {
    if (_departure.difference(_now()).abs() > const Duration(minutes: 15)) {
      if (mounted && token == _token) setState(() => _routeWeather = null);
      return;
    }
    try {
      final result = await widget.weather.refresh(
        WeatherPlace(label: 'Walking route start', coordinates: origin),
      );
      if (!mounted || token != _token) return;
      setState(() {
        _routeWeather = result.weather;
        if (!_manualSelection && _routes.isNotEmpty) {
          _selected = _recommendation.index;
        }
      });
    } catch (_) {
      // keep routing if weather fails
    }
  }

  double _daylightFraction(Map<String, dynamic>? result) {
    final distance = (result?['distance'] as num?)?.toDouble();
    final night = (result?['night'] as num?)?.toDouble();
    if (distance == null ||
        night == null ||
        !distance.isFinite ||
        distance <= 0 ||
        !night.isFinite ||
        night < 0 ||
        night > distance) {
      return double.nan;
    }
    return 1 - night / distance;
  }

  void _choosePreference(RoutePreference preference) {
    if (preference == _preference && !_manualSelection) {
      _settings?.update(preference: preference, preferencePromptSeen: true);
      return;
    }
    setState(() {
      _preference = preference;
      _manualSelection = false;
      if (!_navigating && _routes.isNotEmpty && !_busy) {
        _selected = _recommendation.index;
        _lastFixAt = null;
      }
    });
    if (!_navigating) _fitPoints(allRoutes: true);
    if (_navigating) {
      if (_navigating && !_busy) unawaited(_calculate(navigation: true));
    }
    _settings?.update(preference: preference, preferencePromptSeen: true);
  }

  Widget _routeChoice(RoutePreference preference, {bool single = false}) {
    final choice = _choiceFor(preference);
    final index = choice.index;
    final route = _routes[index];
    final active = single || _preference == preference;
    final colors = Theme.of(context).colorScheme;
    final foreground = active ? const Color(0xff102c3d) : colors.onSurface;
    final secondary = active
        ? const Color(0xff34505a)
        : colors.onSurfaceVariant;
    final icon = switch (preference) {
      RoutePreference.mostShade => Icons.eco_outlined,
      RoutePreference.balanced => Icons.tune,
      RoutePreference.fastest => Icons.bolt,
    };
    final detail = switch (preference) {
      RoutePreference.mostShade => 'Shadiest walk',
      RoutePreference.balanced => 'Shade and time together',
      RoutePreference.fastest => 'Shortest walking time',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: active ? const Color(0xffe8f6f4) : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: active ? const Color(0xff008b88) : colors.outlineVariant,
            width: active ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey(
            single
                ? 'best-route-choice'
                : 'route-preference-${preference.name}',
          ),
          borderRadius: BorderRadius.circular(18),
          onTap: single ? null : () => _choosePreference(preference),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xffc4ebe6)
                        : const Color(0xffedf3f4),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: const Color(0xff006c70)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        single
                            ? 'Best route'
                            : preference == RoutePreference.mostShade
                            ? 'Most shade'
                            : 'Fastest route',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                      ),
                      Text(
                        single
                            ? choice.shadeUnavailable
                                  ? 'Walking route'
                                  : _cloudyDeparture
                                  ? 'Shortest walking time'
                                  : 'Shade + speed'
                            : _cloudyDeparture
                            ? 'Same walk in these conditions'
                            : choice.shadeUnavailable &&
                                  preference != RoutePreference.fastest
                            ? 'Best mapped walk available'
                            : detail,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: secondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(_duration(route) / 60).ceil()} min',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    Text(
                      SettingsScope.distance(context, route.distanceMeters),
                      style: TextStyle(color: secondary),
                    ),
                  ],
                ),
                if (active) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: Color(0xff006c70)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _departure = _now();
    _takeDestination();
  }

  void _takeDestination() {
    final d = widget.destination;
    if (d?.startFromCurrentLocation == true) {
      _start = null;
      _startText.clear();
    }
    _end = d == null
        ? null
        : CityPlace(
            d.name,
            d.address,
            d.location,
            sourceUrl: d.sourceUrl,
            precision: d.precision,
          );
  }

  @override
  void didUpdateWidget(CityTripPanel old) {
    super.didUpdateWidget(old);

    if (!old.active && widget.active && _navigating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_navigating) return;
        _updateNavigation();
        final fix = _location?.fix;
        if (_following &&
            _mapReady &&
            _refreshPolicy.isFresh(fix?.at, _now()) &&
            fix != null) {
          _map.moveAndRotate(
            LatLng(fix.point.latitude, fix.point.longitude),
            17,
            -_heading,
          );
        }
      });
    }
    final d = widget.destination;

    if (old.destination != d &&
        (d?.startFromCurrentLocation == true ||
            !(d != null &&
                _end?.name == d.name &&
                _same(_end?.point, d.location)))) {
      _takeDestination();
      _invalidate();
      _scheduleCalculation();
    }
  }

  bool _same(Coordinates? a, Coordinates? b) =>
      a?.latitude == b?.latitude && a?.longitude == b?.longitude;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = SettingsScope.maybeOf(context);
    final savedPreference = _settings?.routePreference ?? _preference;

    final preference = savedPreference == RoutePreference.balanced
        ? RoutePreference.mostShade
        : savedPreference;
    if (preference != _preference) {
      _preference = preference;
      _manualSelection = false;
      if (_routes.isNotEmpty && !_busy) {
        _selected = _recommendation.index;
        _lastFixAt = null;
      }
    }
    _location = LocationScope.maybeOf(context);
    final p = _location?.position;
    if (_navigating && (_location?.locationAllowed != true || p == null)) {
      _invalidate();
    }
    if (_navigating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateNavigation();
      });
    }
    if (!_navigating &&
        _progress?.arrived != true &&
        _start == null &&
        (_originLat != p?.latitude || _originLon != p?.longitude)) {
      _invalidate();
      _scheduleCalculation();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady && p != null && _routes.isEmpty) {
          if (CityTripService.isInPlanningArea(p)) {
            _map.move(LatLng(p.latitude, p.longitude), 14);
          } else {
            _centerLasVegas();
          }
        }
      });
    }
    _originLat = p?.latitude;
    _originLon = p?.longitude;
  }

  void _scheduleCalculation() {
    final token = _token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _token && _origin != null && _end != null) {
        _calculate();
      }
    });
  }

  @override
  void dispose() {
    _token++;
    _stopNavigation();
    for (final c in [_startText, _endText, _viaText]) {
      c.dispose();
    }
    if (widget.service == null) _service.client.close();
    _map.dispose();
    _drawer.dispose();
    super.dispose();
  }

  Coordinates? get _origin =>
      _start?.point ?? LocationScope.maybeOf(context)?.position;
  CityWalkingRoute? get _route => _routes.isEmpty ? null : _routes[_selected];
  CoolingDestination? get _destination {
    final end = _end;
    if (end == null) return null;
    final selected = widget.destination;
    if (selected != null &&
        selected.name == end.name &&
        _same(selected.location, end.point)) {
      return selected;
    }
    return CoolingDestination(
      id: 'city-trip',
      name: end.name,
      address: end.address,
      location: end.point,
      sourceUrl: end.sourceUrl ?? 'https://www.openstreetmap.org',
      precision: end.precision ?? 'Selected map point',
    );
  }

  void _invalidate() {
    _stopNavigation();
    _token++;
    _routes = [];
    _shades = [];
    _routeWeather = null;
    _routeOrigin = null;
    _remainingVia = null;
    _lastComparison = null;
    _manualSelection = false;
    _selected = 0;
    _error = null;
    _busy = false;
  }

  void _setPlace(bool start, CityPlace? place) {
    setState(() {
      if (start) {
        _start = place;
      } else {
        _end = place;
      }
      _mapTarget = null;
      _invalidate();
    });
    if (!start) {
      if (_destination case final d?) {
        widget.onDestinationSelected?.call(d);
      }
    }
    _fitPoints();
    if (_origin != null && _end != null) _calculate();
  }

  Future<void> _editPlace(bool start) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PlaceSearchSheet(
        service: _service,
        start: start,
        initial: (start ? _start : _end)?.name ?? '',
        locationAvailable: LocationScope.maybeOf(context)?.position != null,
        onSelect: (p) {
          FocusScope.of(context).unfocus();
          Navigator.pop(context);
          _setPlace(start, p);
        },
        onMyLocation: () {
          Navigator.pop(context);
          _setPlace(true, null);
        },
        onMap: () {
          Navigator.pop(context);
          setState(() => _mapTarget = start);
          if (_drawer.isAttached) {
            _drawer.animateTo(
              .22,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        },
      ),
    );
  }

  Future<void> _mapPoint(Coordinates point) async {
    try {
      CityTripService.validatePoint(point);
    } on FormatException catch (e) {
      setState(() => _error = e.message.toString());
      return;
    }
    bool? start = _mapTarget;
    start ??= await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.trip_origin),
              title: const Text('Start here'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Go here'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (!mounted || start == null) return;
    _setPlace(
      start,
      CityPlace(
        start ? 'Selected start' : 'Selected destination',
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
        point,
      ),
    );
  }

  void _centerLasVegas() {
    if (!_mapReady) return;
    final center = CityTripService.planningCenter;
    _map.moveAndRotate(LatLng(center.latitude, center.longitude), 12, 0);
  }

  void _fitPoints({bool allRoutes = false}) {
    if (!_mapReady) return;
    final points = allRoutes && _route != null
        ? _route!.geometry.points
        : [_origin, _end?.point]
              .whereType<Coordinates>()
              .where(CityTripService.isInPlanningArea)
              .toList();
    if (points.isEmpty) {
      _centerLasVegas();
      return;
    }
    if (points.length == 1 || points.every((p) => _same(p, points.first))) {
      _map.move(LatLng(points.first.latitude, points.first.longitude), 15);
      return;
    }
    final height = _map.camera.nonRotatedSize.height;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(),
        padding: height < 420
            ? const EdgeInsets.all(32)
            : EdgeInsets.fromLTRB(
                40,
                190,
                40,
                (height * (_drawer.isAttached ? _drawer.size : .28) + 24).clamp(
                  24.0,
                  height - 270,
                ),
              ),
        maxZoom: 17,
      ),
    );
  }

  Future<void> _showEntireRoute() async {
    setState(() => _following = false);
    if (_mapReady) _map.rotate(0);
    if (_drawer.isAttached) {
      await _drawer.animateTo(
        .28,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    if (mounted) _fitPoints(allRoutes: true);
  }

  Coordinates _parse(String text) {
    final parts = text.split(',');
    if (parts.length != 2) {
      throw const FormatException('Use latitude, longitude.');
    }
    final point = Coordinates(
      latitude: double.parse(parts[0].trim()),
      longitude: double.parse(parts[1].trim()),
    );
    CityTripService.validatePoint(point);
    return point;
  }

  double _duration(CityWalkingRoute route) => route.geometry.durationSeconds;

  Future<Map<String, dynamic>> _calculateShade(
    CityWalkingRoute route, {
    DateTime? departure,
  }) async {
    final geometry = WalkingGeometry(
      points: route.geometry.points,
      durationSeconds: _duration(route),
      segmentSeconds: route.geometry.segmentSeconds,
      sourceUrl: route.geometry.sourceUrl,
      accessReviewed: route.geometry.accessReviewed,
    );
    final adjusted = CityWalkingRoute(
      geometry,
      route.distanceMeters,
      steps: route.steps,
      inferredStreetMeters: route.inferredStreetMeters,
    );
    if (widget.shadeCalculator != null) {
      return widget.shadeCalculator!(adjusted, departure ?? _departure);
    }
    return _shadeData.calculate(geometry, departure ?? _departure);
  }

  Future<void> _recalculateShades() async {
    if (_routes.isEmpty) return;
    final token = ++_token;
    final routes = List<CityWalkingRoute>.of(_routes);
    final departure = _departure;
    setState(() => _busy = true);
    final shades = await _compareShades(routes, departure, token);
    if (!mounted || token != _token) return;
    setState(() {
      _shades = shades;
      _busy = false;
      if (!_manualSelection) _selected = _recommendation.index;
      _lastComparison = _now();
    });
    if (_routeOrigin case final origin?) {
      unawaited(_refreshRouteWeather(origin, token));
    }
    if (_navigating) {
      _lastFixAt = null;
      _updateNavigation();
    }
  }

  Future<List<Map<String, dynamic>?>> _compareShades(
    List<CityWalkingRoute> routes,
    DateTime departure,
    int token,
  ) async {
    final shades = <Map<String, dynamic>?>[];
    for (final route in routes) {
      if (!mounted || token != _token) return shades;
      try {
        shades.add(await _calculateShade(route, departure: departure));
      } catch (error, stack) {
        debugPrint('HeatWatch shade calculation failed: $error\n$stack');
        shades.add({'error': true});
      }
    }
    return shades;
  }

  List<Coordinates> _parseVia() => _viaText.text.trim().isEmpty
      ? <Coordinates>[]
      : _viaText.text.trim().split('\n').map(_parse).toList();

  Future<void> _calculate({bool navigation = false}) async {
    navigation = navigation || _navigating;
    final start = _origin, end = _end;
    if (start == null || end == null) {
      setState(
        () => _error = start == null
            ? 'Choose a start, or enable location in Settings.'
            : 'Choose a destination.',
      );
      return;
    }
    final token = ++_token;
    final previousRoute = navigation && _manualSelection ? _route : null;
    setState(() {
      _busy = true;
      _error = null;
      _rerouting = navigation;
      _navigationError = false;
      _routeWeather = null;
      if (!navigation) {
        _routes = [];
        _shades = [];
        _selected = 0;
      } else {
        _departure = _now();
      }
    });
    try {
      var via = List<Coordinates>.of(
        navigation ? (_remainingVia ?? _parseVia()) : _parseVia(),
      );
      var requestStart = start;
      late List<CityWalkingRoute> routes;
      late List<Map<String, dynamic>?> shades;

      for (var attempt = 0; attempt < 2; attempt++) {
        routes = await _service.walkAlternatives(
          requestStart,
          end.point,
          via: via,
        );
        if (!mounted || token != _token) return;
        for (final route in routes) {
          walkingWaypointOffsets(route, via);
        }
        final departure = _departure;
        shades = await _compareShades(routes, departure, token);
        if (!mounted || token != _token) return;
        if (navigation) {
          final fix = _location?.fix;
          if (!_refreshPolicy.isFresh(fix?.at, _now())) {
            setState(() => _gpsStale = true);
            return;
          }
          final remaining = _remainingVia ?? via;
          final passedStop =
              remaining.length != via.length ||
              List.generate(
                remaining.length,
                (i) => i,
              ).any((i) => !_same(remaining[i], via[i]));
          if (passedStop || walkingDistance(requestStart, fix!.point) > 40) {
            if (attempt == 0) {
              requestStart = fix!.point;
              via = List<Coordinates>.of(remaining);
              _departure = _now();
              continue;
            }
            throw const FormatException(
              'Location moved during the update. Keeping your current route.',
            );
          }
        }
        break;
      }

      setState(() {
        _routes = routes;
        _routeOrigin = requestStart;
        _lastComparison = _now();
        _shades = shades;
        final matched = previousRoute == null || !_manualSelection
            ? null
            : matchingWalkingCorridor(
                routes,
                previousRoute,
                _progress?.alongMeters ?? 0,
              );
        _selected = matched ?? _recommendation.index;
        _manualSelection = matched != null;
      });
      unawaited(_refreshRouteWeather(requestStart, token));
      if (!navigation && _drawer.isAttached) {
        await _drawer.animateTo(
          .60,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      if (!mounted || token != _token) return;
      if (!navigation) _fitPoints(allRoutes: true);
    } catch (e) {
      if (mounted && token == _token) {
        if (navigation) _navigationError = true;
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : 'Walking routes unavailable. Try again.',
        );
      }
    } finally {
      if (mounted && token == _token) {
        setState(() {
          _busy = false;
          _rerouting = false;
        });
        if (_navigating) {
          _lastFixAt = null;
          _updateNavigation();
        }
      }
    }
  }

  Future<void> _pickTime() async {
    final now = _now();
    final day = await showDatePicker(
      context: context,
      initialDate: _departure.isBefore(now.subtract(const Duration(days: 1)))
          ? now
          : _departure,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 7)),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
    );
    if (time == null || !mounted) return;
    setState(() {
      _departure = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
    });
    if (_routes.isNotEmpty) {
      await _recalculateShades();
    } else if (_origin != null && _end != null) {
      await _calculate();
    }
  }

  Widget _endpoint(bool start) {
    final place = start ? _start : _end;
    final title = start
        ? (_start?.name ?? 'Your location')
        : (_end?.name ?? 'Where to?');
    return ListTile(
      key: ValueKey(start ? 'route-start-field' : 'route-destination-field'),
      dense: true,
      leading: Icon(
        start ? Icons.trip_origin : Icons.location_on_outlined,
        color: start ? const Color(0xff1565c0) : const Color(0xffc62828),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        start && _origin == null
            ? 'Location unavailable · tap to choose'
            : place != null
            ? place.name.startsWith('Selected ')
                  ? 'Map pin'
                  : place.address.isNotEmpty
                  ? place.address
                  : start
                  ? 'Starting point'
                  : 'Destination'
            : start
            ? 'Starting point'
            : 'Place or address',
        maxLines: 1,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (place != null)
            FavoriteButton(
              key: ValueKey(start ? 'favorite-departure' : 'favorite-arrival'),
              place: SavedPlace.fromCity(place),
              endpoint: start ? 'departure' : 'arrival',
            ),
          const Icon(Icons.edit_outlined, size: 18),
        ],
      ),
      onTap: () => _editPlace(start),
    );
  }

  List<Widget> _tripContents() {
    final d = _destination, origin = _routeOrigin ?? _origin;
    final route = _route;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Route options',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xff102c3d),
              ),
            ),
          ),
          if (route != null)
            IconButton(
              key: const ValueKey('route-refresh-button'),
              tooltip: 'Refresh routes',
              onPressed: _busy ? null : _calculate,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      TextButton.icon(
        onPressed: _busy || _navigating ? null : _pickTime,
        icon: const Icon(Icons.schedule, size: 18),
        label: Text(
          'Depart ${_departure.month}/${_departure.day} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_departure))}',
        ),
      ),
      const SizedBox(height: 4),
      if (_cloudyDeparture && _routes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Cloudy at departure · fastest walk shown',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xff375c6a)),
          ),
        ),
      if (!_cloudyDeparture &&
          _routes.isNotEmpty &&
          _departure.difference(_now()) > const Duration(minutes: 15))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Scheduled walk · shade assumes clear skies',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xff375c6a)),
          ),
        ),
      if (_routes.isEmpty && !_busy && _error == null)
        Text(
          d == null
              ? 'Search a destination to see walking routes.'
              : origin == null
              ? 'Choose a starting point.'
              : 'Finding a walking route…',
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_error!),
        ),
      if (_error?.contains('accessible entrance') == true)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _mapTarget = true);
              if (_start case final start?) {
                _map.move(
                  LatLng(start.point.latitude, start.point.longitude),
                  16,
                );
              }
              if (_drawer.isAttached) {
                _drawer.animateTo(
                  .22,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Choose public road on map'),
          ),
        ),
      if (_singleChoice)
        _routeChoice(RoutePreference.fastest, single: true)
      else if (_routes.isNotEmpty)
        for (final preference in const [
          RoutePreference.mostShade,
          RoutePreference.fastest,
        ])
          _routeChoice(preference),
      if (_busy) const LinearProgressIndicator(),
      if (route == null) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('route-refresh-button'),
          onPressed: _busy ? null : _calculate,
          icon: const Icon(Icons.route),
          label: const Text('Find walking routes'),
        ),
      ],
      if (route != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('walking-navigation-toggle'),
                  onPressed: _busy && !_navigating
                      ? null
                      : () {
                          if (_navigating) {
                            setState(_stopNavigation);
                          } else {
                            unawaited(_startNavigation());
                          }
                        },
                  icon: Icon(_navigating ? Icons.stop : Icons.navigation),
                  label: Text(
                    _navigating ? 'Stop navigation' : 'Start walking',
                  ),
                ),
              ),
            ],
          ),
        ),
      if (route != null && route.steps.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          'Walking directions',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < route.steps.length; i++)
          ListTile(
            key: ValueKey('walking-step-$i'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              i == route.steps.length - 1
                  ? Icons.location_on_outlined
                  : i == 0
                  ? Icons.directions_walk
                  : Icons.turn_right,
            ),
            title: Text(
              SettingsScope.maybeOf(context)
                      ?.walkingInstruction(route.steps[i].instruction) ??
                  route.steps[i].instruction,
            ),
            subtitle: i == route.steps.length - 1
                ? null
                : Text(_stepDistance(route, i)),
          ),
      ],
      if (_progress != null || _navigating)
        Card(
          child: ListTile(
            key: const ValueKey('walking-navigation-status'),
            leading: const Icon(Icons.directions_walk),
            title: Text(
              _rerouting
                  ? 'Updating walking route…'
                  : _navigationError
                  ? 'Route update unavailable · try again'
                  : _gpsStale
                  ? 'Waiting for GPS…'
                  : _progress == null
                  ? 'Waiting for GPS…'
                  : _settings?.walkingInstruction(_progress!.instruction) ??
                        _progress!.instruction,
            ),
            subtitle: Text(
              _progress == null || route == null
                  ? 'Keep HeatWatch open while walking'
                  : '${SettingsScope.distance(context, _progress!.remainingMeters)} remaining · '
                        '${(_progress!.remainingMeters * _duration(route) / route.distanceMeters / 60).ceil()} min',
            ),
            trailing: IconButton(
              tooltip: 'Follow my location',
              icon: const Icon(Icons.my_location),
              onPressed: () {
                setState(() => _following = true);
                _lastFixAt = null;
                _updateNavigation();
              },
            ),
          ),
        ),
      const SizedBox(height: 24),
    ];
  }

  String _stepDistance(CityWalkingRoute route, int index) {
    final next = index + 1 < route.steps.length
        ? route.steps[index + 1].atMeters
        : route.distanceMeters;
    final meters = (next - route.steps[index].atMeters).clamp(
      0,
      route.distanceMeters,
    );
    return SettingsScope.distance(context, meters.toDouble(), short: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 420;
        final endpoints = Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(20),
          color: colors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _endpoint(true),
              const Divider(height: 1, indent: 54),
              _endpoint(false),
            ],
          ),
        );
        final map = ShadeStreetMap(
          controller: _map,
          routes: _route == null ? [] : [_route!],
          selectedIndex: 0,
          userPosition: _location?.position,
          userHeading: _heading,
          onUserGesture: () {
            if (_following) setState(() => _following = false);
          },
          origin: _origin,
          destination: _end?.point,
          active: widget.active,
          tilesEnabled: widget.tilesEnabled,
          onPointSelected: _mapPoint,
          onRouteSelected: (_) {},
          onReady: () {
            _mapReady = true;
            if (_routes.isNotEmpty) _fitPoints(allRoutes: true);
          },
        );

        if (compact) {
          return Row(
            children: [
              SizedBox(
                width: constraints.maxWidth * .48,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    endpoints,
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _showEntireRoute,
                      icon: const Icon(Icons.fit_screen),
                      label: const Text('Show entire route'),
                    ),
                    if (_mapTarget != null)
                      Text(
                        'Tap the map to set ${_mapTarget! ? 'your start' : 'your destination'}',
                      ),
                    ..._tripContents(),
                  ],
                ),
              ),
              Expanded(child: map),
            ],
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: map),
            Positioned(top: 32, left: 12, right: 12, child: endpoints),
            if (_navigating || _progress?.arrived == true)
              Positioned(
                top: 164,
                left: 12,
                right: 12,
                child: Material(
                  color: colors.primaryContainer,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_walk),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _rerouting
                                    ? 'Updating walking route…'
                                    : _navigationError
                                    ? 'Route update unavailable · try again'
                                    : _gpsStale
                                    ? 'Waiting for GPS…'
                                    : _progress == null
                                    ? 'Waiting for GPS…'
                                    : _settings?.walkingInstruction(
                                            _progress!.instruction,
                                          ) ??
                                          _progress!.instruction,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (_progress != null)
                                Text(
                                  '${SettingsScope.distance(context, _progress!.remainingMeters)} remaining',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_mapTarget != null)
              Positioned(
                top: 184,
                left: 12,
                right: 12,
                child: Material(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      'Tap the map to set ${_mapTarget! ? 'your start' : 'your destination'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Cancel map selection',
                      onPressed: () => setState(() => _mapTarget = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            ListenableBuilder(
              listenable: _drawer,
              builder: (context, _) {
                final size = _drawer.isAttached ? _drawer.size : .28;
                if (size > .52) return const SizedBox.shrink();
                return Positioned(
                  right: 12,
                  bottom: constraints.maxHeight * size + 12,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'route-fit',
                        tooltip: 'Show entire route',
                        backgroundColor: colors.surface,
                        onPressed: _showEntireRoute,
                        child: const Icon(Icons.fit_screen),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'route-location',
                        tooltip: 'Center on my location',
                        backgroundColor: colors.surface,
                        onPressed: () {
                          final p = LocationScope.maybeOf(context)?.position;
                          if (p == null) {
                            setState(
                              () => _error = 'Location unavailable. Choose a start or enable it in Settings.',
                            );
                          } else if (!CityTripService.isInPlanningArea(p)) {
                            _centerLasVegas();
                            setState(
                              () => _error = 'Your location is outside Las Vegas. Choose a start on the map.',
                            );
                          } else if (_mapReady) {
                            setState(() => _following = true);
                            _map.moveAndRotate(
                              LatLng(p.latitude, p.longitude),
                              17,
                              _navigating ? -_heading : 0,
                            );
                          }
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                );
              },
            ),
            DraggableScrollableSheet(
              controller: _drawer,
              initialChildSize: .28,
              minChildSize: .22,
              maxChildSize: .72,
              snap: true,
              snapSizes: const [.28, .50, .72],
              builder: (context, controller) => Material(
                elevation: 8,
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    ..._tripContents(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
