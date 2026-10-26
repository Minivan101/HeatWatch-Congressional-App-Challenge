import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/coordinates.dart';
import '../../../core/services/location_service.dart';
import '../../../core/widgets/feature_header.dart';
import 'local_shade_panel.dart';
import 'city_trip_panel.dart';
import '../services/city_trip_service.dart';
import '../../../core/location/app_location.dart';
import '../../cool_spots/models/cooling_destination.dart';
import '../../heat_guard/services/weather_repository.dart';
import '../../heat_guard/presentation/route_weather_panel.dart';

class ShadeRoutePage extends StatefulWidget {
  const ShadeRoutePage({
    super.key,
    this.locationService = const LocationService(),
    this.walkingService,
    this.coolingDestination,
    this.onClearDestination,
    this.weatherRepository,
    this.active = true,
    this.mapTilesEnabled = true,
    this.onChooseDestination,
    this.onDestinationSelected,
  });

  final LocationService locationService;
  final CityTripService? walkingService;
  final CoolingDestination? coolingDestination;
  final VoidCallback? onClearDestination;
  final WeatherRepository? weatherRepository;
  final bool active, mapTilesEnabled;
  final VoidCallback? onChooseDestination;
  final ValueChanged<CoolingDestination>? onDestinationSelected;

  @override
  State<ShadeRoutePage> createState() => _ShadeRoutePageState();
}

class _ShadeRoutePageState extends State<ShadeRoutePage> {
  bool _isLoading = false;
  Coordinates? _location;
  String? _error;

  Future<void> _useMyLocation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final location = await widget.locationService.getCurrentPosition();
      if (!mounted) return;
      setState(() => _location = location);
    } on LocationAccessException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Location took too long. Please try again.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (LocationScope.maybeOf(context) != null &&
        widget.weatherRepository != null) {
      return CityTripPanel(
        service: widget.walkingService,
        tilesEnabled: widget.mapTilesEnabled,
        destination: widget.coolingDestination,
        weather: widget.weatherRepository!,
        active: widget.active,
        onCoolingDirectory: widget.onChooseDestination,
        onDestinationSelected: widget.onDestinationSelected,
        onClearDestination: widget.onClearDestination,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const FeatureHeader(
          icon: Icons.route,
          title: 'Shade Route',
          description: 'Find walking routes with estimated building shade.',
        ),
        const SizedBox(height: 24),
        if (widget.coolingDestination != null &&
            widget.weatherRepository != null)
          RouteWeatherPanel(
            destination: widget.coolingDestination!,
            origin: _location,
            repository: widget.weatherRepository!,
            active: widget.active,
            onClearDestination: widget.onClearDestination,
          ),
        if (widget.coolingDestination == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your trip',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Choose a cooling location to see your plan in one place.',
                  ),
                  if (widget.onChooseDestination != null)
                    FilledButton(
                      onPressed: widget.onChooseDestination,
                      child: const Text('Choose cooling destination'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start with your location',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'HeatWatch asks for location only when you tap below. '
                  'Trip weather checks share the selected coordinates with Open-Meteo and NWS.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _useMyLocation,
                  icon: _isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    _isLoading ? 'Finding location…' : 'Use my location',
                  ),
                ),
                if (_location case final location?) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Location found: '
                    '${location.latitude.toStringAsFixed(3)}, '
                    '${location.longitude.toStringAsFixed(3)}',
                  ),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.coolingDestination != null &&
            widget.weatherRepository == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Planned cooling destination',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(widget.coolingDestination!.name),
                  Text(widget.coolingDestination!.address),
                  Text(widget.coolingDestination!.precision),
                  const Text(
                    'Officially listed location. Confirm cooling availability and a public pedestrian entrance before visiting.',
                  ),
                  const Text(
                    'A walking or shade route to this destination has not been calculated.',
                  ),
                  TextButton(
                    onPressed: widget.onClearDestination,
                    child: const Text('Clear planned destination'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const LocalShadePanel(),
        const SizedBox(height: 16),
        const Text(
          'Real walking routes need confirmed endpoints and pedestrian access. The local shade calculator does not require paid Maps usage.',
        ),
      ],
    );
  }
}
