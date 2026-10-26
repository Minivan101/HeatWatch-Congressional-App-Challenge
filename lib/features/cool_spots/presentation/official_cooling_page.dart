import 'cooling_discovery_map.dart';
import '../../../core/saved_places/saved_places.dart';
import '../../../core/saved_places/saved_places_widgets.dart';
import 'cooling_photo_details.dart';
import '../../heat_guard/presentation/weather_overview.dart';

import 'dart:convert';

import '../../shade_route/services/city_trip_service.dart';
import '../models/cooling_discovery.dart';
import '../models/unofficial_cooling_directory.dart';
import 'unofficial_place_report.dart';
import 'cooling_place_map_page.dart';

import 'package:flutter/material.dart';

import '../../../core/location/app_location.dart';
import '../../../core/settings/app_settings.dart';

import 'package:flutter/services.dart';

import '../../../core/models/coordinates.dart';
import '../../../core/services/location_service.dart';
import '../models/cooling_destination.dart';

import '../models/official_cooling_directory.dart';
import '../services/cooling_actions.dart';
import '../services/cooling_directory_repository.dart';

class OfficialCoolingPage extends StatefulWidget {
  const OfficialCoolingPage({
    super.key,
    this.loader,
    this.unofficialLoader,
    this.repository,
    this.discoveryAssetsLoader,
    this.actions = const CoolingActions(),
    this.locationService = const LocationService(),
    this.onDestinationSelected,
    this.mapTilesEnabled = true,
  });

  final Future<OfficialCoolingDirectory> Function()? loader;
  final Future<UnofficialCoolingDirectory> Function()? unofficialLoader;
  final CoolingDirectoryRepository? repository;
  final bool mapTilesEnabled;
  final Future<Map<String, dynamic>> Function()? discoveryAssetsLoader;
  final CoolingActions actions;
  final LocationService locationService;
  final ValueChanged<CoolingDestination>? onDestinationSelected;

  @override
  State<OfficialCoolingPage> createState() => _OfficialCoolingPageState();
}

class _OfficialCoolingPageState extends State<OfficialCoolingPage> {
  OfficialCoolingDirectory? _official;
  UnofficialCoolingDirectory? _community;
  final _searchController = TextEditingController();
  final _citySearch = CityTripService();
  late final _repository = widget.repository ?? CoolingDirectoryRepository();
  Map<String, dynamic> _zipPoints = {}, _photos = {};
  Coordinates? _origin, _searchPoint;
  int _radiusMiles = 5;
  String _category = 'All', _query = '', _area = '', _textQuery = '';
  String? _loadError, _searchError;
  bool _loading = true, _searching = false, _mapView = false;
  int _limit = 10, _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    Future<void> official() async {
      try {
        final value = widget.loader != null
            ? await widget.loader!()
            : (await _repository.load()).directory;
        if (mounted) setState(() => _official = value);
      } catch (_) {
        if (mounted) {
          setState(() => _loadError = 'Some saved places could not be loaded.');
        }
      }
    }

    Future<void> community() async {
      try {
        final value = widget.unofficialLoader != null
            ? await widget.unofficialLoader!()
            : UnofficialCoolingDirectory.parse(
                jsonDecode(
                  await rootBundle.loadString(
                    'data/cooling_centers/unofficial_directory.json',
                  ),
                ),
              );
        if (mounted) setState(() => _community = value);
      } catch (_) {
        if (mounted) {
          setState(() => _loadError = 'Some saved places could not be loaded.');
        }
      }
    }

    Future<void> assets() async {
      final data = widget.discoveryAssetsLoader != null
          ? await widget.discoveryAssetsLoader!()
          : <String, dynamic>{
              'points': (jsonDecode(
                await rootBundle.loadString(
                  'assets/cool_spots/zip_points.json',
                ),
              ) as Map)['points'],
              'photos': jsonDecode(
                await rootBundle.loadString('assets/cool_spots/photos.json'),
              ),
            };
      if (mounted) {
        setState(() {
          _zipPoints = Map<String, dynamic>.from(data['points'] as Map);
          _photos = Map<String, dynamic>.from(data['photos'] as Map);
        });
      }
    }

    await Future.wait([
      official(),
      community(),
      assets().catchError((Object _) {
        if (mounted) {
          setState(
            () => _loadError = 'Search data could not be loaded. Try again.',
          );
        }
      }),
    ]);
    if (mounted) {
      setState(() => _loading = false);
      if (RegExp(r'^\d{5}(?:-\d{4})?$').hasMatch(_query)) _changed(_query);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = LocationScope.maybeOf(context);
    if (shared != null) {
      final point = shared.position;
      if (_origin?.latitude != point?.latitude ||
          _origin?.longitude != point?.longitude) {
        _origin = point;
      }
    }
  }

  @override
  void dispose() {
    _searchGeneration++;
    _citySearch.client.close();
    _searchController.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _searchGeneration++;
    final q = value.trim();
    setState(() {
      _query = q;
      _limit = 10;
      _searchError = null;
      _searching = false;
      if (q.isEmpty) {
        _searchPoint = null;
        _area = '';
        _textQuery = '';
      } else if (RegExp(r'^\d{5}(?:-\d{4})?$').hasMatch(q)) {
        final zip = q.substring(0, 5),
            point = _zipPoints[q.substring(0, 5)] as List?;
        _textQuery = '';
        _area = zip;
        _searchPoint = point == null
            ? null
            : Coordinates(
                latitude: (point[0] as num).toDouble(),
                longitude: (point[1] as num).toDouble(),
              );
        if (point == null) _searchError = 'That ZIP is not in the saved Las Vegas-area directory. Try another ZIP or search a city.';
      } else {
        _textQuery = q;
        if (RegExp(r'^\d{1,4}$').hasMatch(q)) {
          _searchError = 'Enter all five digits of a ZIP code.';
        }
      }
    });
  }

  Future<void> _submit(String value) async {
    if (value.trim().isEmpty ||
        RegExp(r'^\d{5}(?:-\d{4})?$').hasMatch(value.trim())) {
      return;
    }
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final choices = await _citySearch.search(value);
      if (!mounted || generation != _searchGeneration) return;
      if (choices.isEmpty) {
        setState(
          () => _searchError =
              'No search point found. Try a ZIP or a more specific address.',
        );
        return;
      }
      final chosen = choices.length == 1
          ? choices.single
          : await showModalBottomSheet<CityPlace>(
              context: context,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('Choose a search location')),
                    for (final choice in choices)
                      ListTile(
                        title: Text(choice.name),
                        subtitle: Text(choice.address),
                        onTap: () => Navigator.pop(context, choice),
                      ),
                  ],
                ),
              ),
            );
      if (!mounted || generation != _searchGeneration || chosen == null) return;
      setState(() {
        _searchPoint = chosen.point;
        _area = chosen.name;
        _textQuery = '';
        _limit = 10;
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(
          () => _searchError =
              'Location search is unavailable. Try a five-digit ZIP instead.',
        );
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  bool _isOfficial(Map<String, dynamic> place) =>
      _official?.stations.any((s) => s['id'] == place['id']) ?? false;
  void _details(Map<String, dynamic> place, {bool allowDestination = true}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _isOfficial(place)
            ? _StationReport(
                station: place,
                discoveryMetadata: _photos[place['id']] as Map?,
                origin: _origin,
                directory: _official!,
                actions: widget.actions,
                onDestinationSelected: allowDestination
                    ? widget.onDestinationSelected
                    : null,
              )
            : UnofficialPlaceReport(
                place: place,
                discoveryMetadata: _photos[place['id']] as Map?,
                origin: _origin,
                directory: _community!,
                actions: widget.actions,
                onDestinationSelected: allowDestination
                    ? widget.onDestinationSelected
                    : null,
              ),
      ),
    );
  }

  void _map(Map<String, dynamic> place) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoolingPlaceMapPage(
          place: place,
          official: _isOfficial(place),
          origin: _origin,
          tilesEnabled: widget.mapTilesEnabled,
          onDetails: (_) => _details(place, allowDestination: false),
          onDestinationSelected: widget.onDestinationSelected,
        ),
      ),
    );
  }

  Future<void> _directions(Map<String, dynamic> place) async {
    var shadeSupported = widget.onDestinationSelected != null;
    if (shadeSupported) {
      try {
        CityTripService.validatePoint(
          CoolingDestination.fromStation(place).location,
        );
      } on FormatException {
        shadeSupported = false;
      }
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * .8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              const ListTile(title: Text('Directions')),
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Google Maps'),
                subtitle: const Text('Open walking directions'),
                onTap: () => Navigator.pop(sheet, 'google'),
              ),
              if (widget.onDestinationSelected != null)
                ListTile(
                  leading: const Icon(Icons.route),
                  title: const Text('ShadeMap'),
                  subtitle: Text(
                    shadeSupported
                        ? 'Compare walking routes by shade'
                        : 'Outside the ShadeMap planning area',
                  ),
                  onTap: shadeSupported
                      ? () => Navigator.pop(sheet, 'shade')
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'shade') {
      widget.onDestinationSelected!(CoolingDestination.fromStation(place));
      return;
    }
    if (choice != 'google') return;
    final opened = await widget.actions.directions(place, origin: _origin);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open directions. Try again.')),
      );
    }
  }

  Future<void> _directoryInfo() async {
    String? error;
    bool busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About nearby places',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'ZIP searches use saved Census representative points, not ZIP boundaries. Distances are straight-line; walking routes can be longer. This is a sourced directory, not a complete inventory.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Facility type does not imply emergency cooling-center activation or unrestricted visitor access. Published hours, access notes and evidence are in each place’s details.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Facility photographs come from their operator or municipality. A neutral illustration appears where a matched photo is unavailable.',
                ),
                if (error != null) Text(error!),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final snapshot = await _repository.refresh();
                            if (mounted) {
                              setState(() => _official = snapshot.directory);
                            }
                          } catch (_) {
                            error = 'Directory update failed. Saved locations remain available.';
                          }
                          if (context.mounted) update(() => busy = false);
                        },
                  child: Text(
                    busy
                        ? 'Updating…'
                        : error != null
                        ? 'Retry check'
                        : 'Check directory updates',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        SettingsScope.maybeOf(context)?.radius(_radiusMiles) ??
        '$_radiusMiles miles';
    final base = Theme.of(context);
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff006b8f),
      brightness: base.brightness,
    );
    final center = _searchPoint ?? _origin;
    final label = _searchPoint != null ? _area : 'your location';
    final places = center == null || _searchError != null
        ? <Map<String, dynamic>>[]
        : nearbyCoolingPlaces(
            [...?_official?.stations, ...?_community?.places],
            center,
            category: _category,
            query: _textQuery,
            radiusMiles: _radiusMiles,
          );
    return Theme(
      data: base.copyWith(colorScheme: colors),
      child: Builder(
        builder: (context) => ColoredBox(
          color: colors.surfaceContainerLow,
          child: ListView(
            padding: EdgeInsets.symmetric(
              vertical: 16,
              horizontal: MediaQuery.sizeOf(context).width > 800
                  ? (MediaQuery.sizeOf(context).width - 760) / 2
                  : 16,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cool Spots',
                      style: base.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'About nearby places',
                    onPressed: _directoryInfo,
                    icon: const Icon(Icons.info_outline),
                  ),
                  IconButton(
                    tooltip: 'Use shared location',
                    icon: const Icon(Icons.my_location),
                    onPressed: () {
                      _searchController.clear();
                      _changed('');
                    },
                  ),
                ],
              ),
              const Text('A cooler place, closer to you.'),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: _changed,
                onSubmitted: _submit,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search ZIP, city or place',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            _changed('');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final category in coolingCategories)
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() {
                        _category = category;
                        _limit = 10;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<int>(
                  key: const ValueKey('cooling-radius'),
                  value: _radiusMiles,
                  isExpanded: true,
                  style: base.textTheme.bodyMedium,
                  itemHeight: null,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(Icons.expand_more),
                  items: [
                    for (final miles in coolingRadiusChoices)
                      DropdownMenuItem(
                        value: miles,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Within ${SettingsScope.maybeOf(context)?.radius(miles) ?? '$miles miles'}',
                          ),
                        ),
                      ),
                  ],
                  onChanged: (miles) {
                    if (miles == null) return;
                    setState(() {
                      _radiusMiles = miles;
                      _limit = 10;
                    });
                  },
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.map_outlined),
                    label: Text('Map'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_list_outlined),
                    label: Text('List'),
                  ),
                ],
                selected: {_mapView},
                onSelectionChanged: (s) => setState(() => _mapView = s.single),
              ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (_loadError != null) ...[
                Text(_loadError!),
                TextButton(
                  onPressed: _load,
                  child: const Text('Retry saved directory'),
                ),
              ],
              if (_searchError != null) Text(_searchError!),
              if (center == null && _searchError == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Search a ZIP or city, or share your location in Settings.',
                  ),
                ),
              if (center != null && _searchError == null) ...[
                Text(
                  '${places.length} ${places.length == 1 ? 'place' : 'places'} within $radius of $label',
                  style: base.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Nearest first · straight-line distance',
                  style: TextStyle(fontSize: 12),
                ),
                if (_mapView && places.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: CoolingDiscoveryMap(
                      key: ValueKey(
                        '${center.latitude}-${center.longitude}-$_category-$_textQuery-$_radiusMiles',
                      ),
                      places: places,
                      origin: center,
                      tilesEnabled: widget.mapTilesEnabled,
                      onSelected: _map,
                    ),
                  ),
                if (places.isEmpty && !_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No matching places within $radius. Try another category or search location.',
                    ),
                  ),
                for (final place in places.take(_limit))
                  _DiscoveryCard(
                    place: place,
                    origin: center,
                    photo: _photos[place['id']] as Map?,
                    onMap: () => _map(place),
                    onDetails: () => _details(place),
                    onDirections: () => _directions(place),
                  ),
                if (places.length > _limit)
                  TextButton(
                    onPressed: () => setState(() => _limit += 10),
                    child: Text('Show more (${places.length - _limit})'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.place,
    required this.origin,
    required this.photo,
    required this.onMap,
    required this.onDetails,
    required this.onDirections,
  });
  final Map<String, dynamic> place;
  final Coordinates origin;
  final Map? photo;
  final VoidCallback onMap, onDetails, onDirections;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methods = place['methods'] as List? ?? const [];
    final type = coolingCategory(place)!;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 104,
        height: 126,
        child: photo?['asset'] is String
            ? Image.asset(
                photo!['asset'] as String,
                fit: BoxFit.cover,
                semanticLabel: '${place['name']} facility photo',
                errorBuilder: (_, _, _) => _placeholder(theme),
              )
            : _placeholder(theme),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                place['name'] as String,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FavoriteButton(
              place: SavedPlace.fromDestination(
                CoolingDestination.fromStation(place),
              ),
            ),
            SizedBox(
              width: 28,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Place details',
                onPressed: onDetails,
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
            ),
          ],
        ),
        Text(
          '${SettingsScope.distance(context, CoolingActions.distanceMeters(origin, place['coordinates'] as Map))} · $type',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (place['scopeLabel'] is String) ...[
          const SizedBox(height: 4),
          Text(place['scopeLabel'] as String, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 6),
        Text(
          photo?['displayAddress'] as String? ?? place['address'] as String,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (methods.contains('airConditioning') && type != 'Parks')
              _amenity(context, Icons.ac_unit, 'AC'),
            if (methods.contains('drinkingWater'))
              _amenity(context, Icons.water_drop_outlined, 'Water'),
            for (final amenity in (photo?['amenities'] as List? ?? const []))
              switch (amenity) {
                'shade' => _amenity(context, Icons.park_outlined, 'Shade'),
                'seating' => _amenity(context, Icons.chair_outlined, 'Seating'),
                'restrooms' => _amenity(
                  context,
                  Icons.wc_outlined,
                  'Restrooms',
                ),
                'wifi' => _amenity(context, Icons.wifi, 'Wi-Fi'),
                'food' => _amenity(context, Icons.restaurant_outlined, 'Food'),
                _ => const SizedBox.shrink(),
              },
          ],
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('cooling-map-${place['id']}'),
        onTap: onMap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.5
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [image, const SizedBox(height: 10), details],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          image,
                          const SizedBox(width: 12),
                          Expanded(child: details),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onDirections,
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: const Text('Directions'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => ColoredBox(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        coolingCategory(place) == 'Parks'
            ? Icons.park_outlined
            : Icons.location_city_outlined,
        size: 36,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
  Widget _amenity(BuildContext context, IconData icon, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}

List<String> _publishedHours(Map<String, dynamic> assertion) {
  final printed = assertion['hoursLinesAsPrinted'];
  if (printed is List && printed.isNotEmpty) return printed.cast<String>();
  final shared = assertion['sharedHoursApplied'];
  if (shared is String && shared.isNotEmpty) return [shared];
  final properties = assertion['originalFeature']?['properties'];
  if (properties is! Map) return [];
  return [
    for (var n = 1; n <= 5; n++)
      if (properties['Hours$n'] is String &&
          (properties['Hours$n'] as String).trim().isNotEmpty)
        [
          properties['Days$n'],
          properties['Hours$n'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
  ];
}

class _StationReport extends StatelessWidget {
  const _StationReport({
    required this.station,
    this.origin,
    required this.directory,
    required this.actions,
    this.onDestinationSelected,
    this.discoveryMetadata,
  });
  final Map<String, dynamic> station;
  final Map? discoveryMetadata;
  final Coordinates? origin;
  final OfficialCoolingDirectory directory;
  final CoolingActions actions;
  final ValueChanged<CoolingDestination>? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final shared = LocationScope.maybeOf(context);
    final currentOrigin = shared == null ? origin : shared.position;
    final coordinates = station['coordinates'] as Map?;
    final records =
        (station['assertions'] as List)
            .cast<Map<String, dynamic>>()
            .where(
              (a) =>
                  _publishedHours(a).isNotEmpty &&
                  directory.source(a['sourceId'] as String)['language'] == 'en',
            )
            .toList()
          ..sort((a, b) {
            final retrieved =
                (directory.source(b['sourceId'] as String)['retrievedOn']
                        as String)
                    .compareTo(
                      directory.source(a['sourceId'] as String)['retrievedOn']
                          as String,
                    );
            if (retrieved != 0) return retrieved;
            final period = (b['activationEnd'] as String? ?? '').compareTo(
              a['activationEnd'] as String? ?? '',
            );
            if (period != 0) return period;

            return (b['sourcePage'] != null ? 1 : 0).compareTo(
              a['sourcePage'] != null ? 1 : 0,
            );
          });
    final latest = records.isEmpty ? null : records.first;
    return Scaffold(
      appBar: AppBar(
        title: Text(station['name'] as String),
        actions: const [CurrentTemperatureDisplay()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          CoolingPhotoDetails(metadata: discoveryMetadata, actions: actions),
          Text(station['address'] as String),
          if (currentOrigin != null && coordinates != null)
            Text(
              '${SettingsScope.distance(context, CoolingActions.distanceMeters(currentOrigin, coordinates))} from your location · straight-line',
            )
          else
            const Text('Distance: enable location in Settings'),
          Wrap(
            spacing: 8,
            children: [
              _OpenButton(
                label: 'Open phone dialer',
                action: () => actions.dial(station['phone'] as String),
              ),
              _CopyButton(
                label: 'Copy contact number',
                value: station['phone'] as String,
              ),
              _CopyButton(
                label: 'Copy address',
                value: station['address'] as String,
              ),
            ],
          ),
          if (coordinates != null && onDestinationSelected != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onDestinationSelected!(CoolingDestination.fromStation(station));
              },
              icon: const Icon(Icons.route),
              label: const Text('Select as planned destination'),
            ),
          Text('Contact: ${station['phone']}'),
          if (latest != null) ...[
            const Text('Published hours'),
            Text(_publishedHours(latest).join(' · ')),
            if (latest['activationStart'] != null &&
                latest['activationEnd'] != null)
              Text(
                "Published dates: ${latest['activationStart']} – ${latest['activationEnd']}",
              ),
          ],
          const SizedBox(height: 8),

          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${(station['assertions'] as List).length} published records',
            ),
            children: [
              for (final assertion
                  in (station['assertions'] as List)
                      .cast<Map<String, dynamic>>())
                _AssertionReport(
                  assertion: assertion,
                  source: directory.source(assertion['sourceId'] as String),
                  actions: actions,
                ),
            ],
          ),
          if ((station['reviewNotes'] as List).isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Source differences'),
              children: [
                for (final note in station['reviewNotes'] as List)
                  Text(note as String),
              ],
            ),
          if (coordinates != null)
            _OpenButton(
              label: 'Location source',
              action: () =>
                  actions.openSource(coordinates['sourceUrl'] as String),
            ),
        ],
      ),
    );
  }
}

class _AssertionReport extends StatelessWidget {
  const _AssertionReport({
    required this.assertion,
    required this.source,
    required this.actions,
  });
  final Map<String, dynamic> assertion;
  final Map<String, dynamic> source;
  final CoolingActions actions;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: ValueKey('assertion-${assertion['stationId']}-${source['id']}'),
      title: Text('${source['id']} · ${source['language']}'),
      subtitle: Text(
        assertion['activationStart'] == null
            ? 'No published activation dates'
            : 'Activation ${assertion['activationStart']} – ${assertion['activationEnd']}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(source['hostingProvenance'] as String),
              Text(
                'Retrieved ${source['retrievedOn']}. Publication date: ${source['publicationDate'] ?? 'not supplied'}.',
              ),
              if (assertion['sourcePage'] != null)
                Text('Flyer page ${assertion['sourcePage']}'),
              SelectableText(
                (assertion['rawText'] ?? assertion['rawPanelText']) as String,
              ),
              if (assertion['sharedHoursApplied'] != null)
                Text(
                  'Shared library header: ${assertion['sharedHoursApplied']}',
                ),
              if (assertion.containsKey('petsPolicy'))
                Text(
                  'Flyer pet footnote: ${assertion['petsPolicy'] ?? 'not specified'}',
                ),
              _CopyButton(
                label: 'Copy source link',
                value: source['url'] as String,
              ),
              _OpenButton(
                label: 'Open source',
                action: () => actions.openSource(source['url'] as String),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.copy),
    label: Text(label),
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label: copied')));
      }
    },
  );
}

class _OpenButton extends StatefulWidget {
  const _OpenButton({required this.label, required this.action});
  final String label;
  final Future<bool> Function() action;
  @override
  State<_OpenButton> createState() => _OpenButtonState();
}

class _OpenButtonState extends State<_OpenButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            var opened = false;
            try {
              opened = await widget.action();
            } catch (_) {
              // show a message below
            }
            if (!mounted || !context.mounted) return;
            setState(() => _busy = false);
            if (!opened) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open. Try again.')),
              );
            }
          },
    child: Text(widget.label),
  );
}
