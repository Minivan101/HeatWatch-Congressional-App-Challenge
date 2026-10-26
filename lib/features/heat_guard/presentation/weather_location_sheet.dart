import 'package:flutter/material.dart';

import '../../../core/location/app_location.dart';
import '../../shade_route/services/city_trip_service.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/models/coordinates.dart';
import '../models/free_weather.dart';

void showWeatherLocationSheet(
  BuildContext context, {
  required ValueChanged<WeatherPlace> onSelected,
}) {
  final shared = LocationScope.maybeOf(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        WeatherLocationSheet(onSelected: onSelected, shared: shared),
  );
}

class WeatherLocationSheet extends StatefulWidget {
  const WeatherLocationSheet({
    super.key,
    required this.onSelected,
    this.shared,
  });
  final ValueChanged<WeatherPlace> onSelected;
  final AppLocation? shared;
  @override
  State<WeatherLocationSheet> createState() => _WeatherLocationSheetState();
}

class _WeatherLocationSheetState extends State<WeatherLocationSheet> {
  final query = TextEditingController(), service = CityTripService();
  List<CityPlace> places = [];
  String? error;
  bool busy = false;
  int request = 0;
  @override
  void dispose() {
    query.dispose();
    service.client.close();
    super.dispose();
  }

  void select(WeatherPlace place) {
    widget.onSelected(place);
    Navigator.pop(context);
  }

  Future<void> search() async {
    final token = ++request;
    setState(() {
      busy = true;
      error = null;
      places = [];
    });
    try {
      final q = query.text.trim();
      List<CityPlace> result;
      if (RegExp(r'^\d{5}(?:-\d{4})?$').hasMatch(q)) {
        final data = jsonDecode(
          await rootBundle.loadString('assets/cool_spots/zip_points.json'),
        ) as Map;
        final point = (data['points'] as Map)[q.substring(0, 5)] as List?;
        result = point == null
            ? []
            : [
                CityPlace(
                  q.substring(0, 5),
                  'ZIP representative point · neighboring areas included',
                  Coordinates(
                    latitude: (point[0] as num).toDouble(),
                    longitude: (point[1] as num).toDouble(),
                  ),
                ),
              ];
      } else {
        result = await service.search(q);
      }
      if (!mounted || token != request) return;
      setState(() {
        places = result;
        if (result.isEmpty) {
          error = 'No matching places. Try a Las Vegas city, ZIP or address.';
        }
      });
    } catch (_) {
      if (mounted && token == request) {
        setState(
          () => error =
              'Search unavailable. Try again or choose the Las Vegas map area.',
        );
      }
    } finally {
      if (mounted && token == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Weather location',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Close location picker',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text(
            'Choose a Las Vegas area for forecasts. This does not change your shared GPS location.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: query,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Search ZIP, city or address',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search weather location',
                onPressed: busy ? null : search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onSubmitted: (_) => search(),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          for (final p in places)
            ListTile(
              title: Text(p.name),
              subtitle: Text(p.address),
              onTap: () =>
                  select(WeatherPlace(label: p.name, coordinates: p.point)),
            ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Las Vegas map area'),
            onTap: () => select(WeatherPlace.savedArea),
          ),
          if (widget.shared?.position case final point?)
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Use shared device location'),
              onTap: () => select(
                WeatherPlace(label: 'Your location', coordinates: point),
              ),
            )
          else if (widget.shared != null)
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Choose shared location access'),
              onTap: () async {
                Navigator.pop(context);
                await showLocationChoice(context, widget.shared!);
              },
            ),
        ],
      ),
    ),
  );
}
