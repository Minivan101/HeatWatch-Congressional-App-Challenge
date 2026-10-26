import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart scripts/import_pilot_walking_route.dart saved-ors-response.json',
    );
    exitCode = 64;
    return;
  }
  try {
    final response = jsonDecode(await File(args.single).readAsString());
    final profile = response['metadata']?['query']?['profile'];
    if (profile != 'foot-walking' ||
        response['type'] != 'FeatureCollection' ||
        response['features'] is! List ||
        (response['features'] as List).isEmpty) {
      throw const FormatException(
        'Requires an actual ORS foot-walking GeoJSON response with metadata.',
      );
    }
    final buildings = LocalShadeBuildings(
      jsonDecode(
        await File('data/buildings/pilot/buildings.json').readAsString(),
      ) as Map<String, dynamic>,
    );
    final routes = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final feature in response['features']) {
      final route = WalkingGeometry.fromOrsFeature(
        feature as Map<String, dynamic>,
        profile: profile as String,
        accessReviewed: false,
      );

      const LocalShadeCalculator().calculate(route, buildings, DateTime.now());
      final points = route.points
          .map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
          .toList();
      if (!seen.add(jsonEncode(points))) continue;
      routes.add({
        'name': 'Walking candidate ${routes.length + 1}',
        'points': points,
        'durationSeconds': route.durationSeconds,
        'sourceUrl': route.sourceUrl,
        'accessReviewed': false,
      });
    }
    final target = File('data/buildings/pilot/routes.json');
    final staged = File('${target.path}.tmp');
    await staged.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'routes': routes,
        'importedAt': DateTime.now().toUtc().toIso8601String(),
        'sourceFile': args.single,
        'metadata': response['metadata'],
        'note': 'Sourced walking candidates; exact public endpoints and access require review.',
      }),
    );
    await staged.rename(target.path);
    stdout.writeln(
      'Imported ${routes.length} distinct walking candidates; pedestrian access remains unverified.',
    );
  } catch (e) {
    stderr.writeln('Route import refused: $e');
    exitCode = 1;
  }
}
