import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/core/models/coordinates.dart';

Future<void> main() async {
  final directory = jsonDecode(
    await File('data/cooling_centers/official_directory.json').readAsString(),
  );
  Coordinates point(String name) {
    final c = (directory['stations'] as List).firstWhere(
      (s) => s['name'] == name,
    )['coordinates'];
    return Coordinates(
      latitude: (c['latitude'] as num).toDouble(),
      longitude: (c['longitude'] as num).toDouble(),
    );
  }

  final service = CityTripService();
  try {
    final places = await service.search('Summerlin Library');
    final route = await service.walk(
      point('Summerlin Library'),
      point('Rainbow Library'),
    );
    final raw = jsonDecode(
      await File('data/buildings/las_vegas/buildings.json').readAsString(),
    ) as Map<String, dynamic>;
    String? status;
    double? shade;
    try {
      shade = const LocalShadeCalculator()
          .calculate(
            route.geometry,
            LocalShadeBuildings(trimBuildings(raw, route.geometry.points)),
            DateTime.utc(2026, 10, 4, 21),
          )
          .modeledShadeFraction;
    } catch (e) {
      status = e.toString();
    }
    stdout.writeln(
      jsonEncode({
        'places': places.length,
        'routePoints': route.geometry.points.length,
        'distanceMeters': route.distanceMeters,
        'durationSeconds': route.geometry.durationSeconds,
        'shade': shade,
        'shadeStatus': status,
      }),
    );
  } finally {
    service.client.close();
  }
}
