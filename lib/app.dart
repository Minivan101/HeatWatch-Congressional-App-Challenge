import 'package:flutter/material.dart';

import 'core/widgets/home_shell.dart';
import 'core/saved_places/saved_places.dart';
import 'features/heat_guard/services/weather_repository.dart';
import 'core/settings/app_settings.dart';
import 'core/location/app_location.dart';
import 'core/services/location_service.dart';
import 'features/shade_route/services/city_trip_service.dart';
import 'features/heat_guard/presentation/weather_overview.dart';

class HeatWatchApp extends StatefulWidget {
  const HeatWatchApp({
    super.key,
    this.settings,
    this.savedPlaces,
    this.weatherRepository,
    this.promptLocation = true,
    this.locationService = const LocationService(),
    this.walkingService,
    this.mapTilesEnabled = true,
    this.demoControls,
  });
  final bool promptLocation, mapTilesEnabled;
  final Widget? demoControls;
  final LocationService locationService;
  final CityTripService? walkingService;
  final AppSettings? settings;
  final SavedPlaces? savedPlaces;
  final WeatherRepository? weatherRepository;
  @override
  State<HeatWatchApp> createState() => _HeatWatchAppState();
}

class _HeatWatchAppState extends State<HeatWatchApp> {
  late final AppSettings _settings = widget.settings ?? AppSettings();
  late final AppLocation _location = AppLocation(
    _settings,
    service: widget.locationService,
  );
  late final SavedPlaces _savedPlaces = widget.savedPlaces ?? SavedPlaces();
  final WeatherOverview _overview = WeatherOverview();
  @override
  void initState() {
    super.initState();
    _settings.load();
    _savedPlaces.load();
  }

  @override
  void dispose() {
    if (widget.savedPlaces == null) _savedPlaces.dispose();
    _location.dispose();
    _overview.dispose();
    if (widget.settings == null) _settings.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF007A7A),
      brightness: brightness,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF3F7FA)
        : const Color(0xFF10283F),
  );
  @override
  Widget build(BuildContext context) => SavedPlacesScope(
    places: _savedPlaces,
    child: SettingsScope(
      settings: _settings,
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => LocationScope(
          location: _location,
          child: WeatherOverviewScope(
            overview: _overview,
            child: MaterialApp(
              title: 'HeatWatch',
              theme: _theme(Brightness.light),
              darkTheme: _theme(Brightness.dark),
              themeMode: _settings.themeMode,
              home: HomeShell(
                demoControls: widget.demoControls,
                promptLocation: widget.promptLocation,
                walkingService: widget.walkingService,
                weatherRepository: widget.weatherRepository,
                mapTilesEnabled: widget.mapTilesEnabled,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
