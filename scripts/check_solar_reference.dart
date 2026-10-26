library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';

Map<String, Object> compareSolarReference(Map<String, dynamic> reference) {
  if (reference['schemaVersion'] != 1 ||
      reference['cases'] is! List ||
      (reference['cases'] as List).isEmpty) {
    throw const FormatException('Invalid independent solar reference.');
  }
  const rad = math.pi / 180;
  var maxElevation = 0.0, maxAzimuth = 0.0, maxDirection = 0.0;
  var horizonDifferences = 0,
      outsideHorizonBandDifferences = 0,
      nearHorizon = 0;
  List<dynamic>? worst;
  for (final raw in reference['cases'] as List) {
    final row = raw as List<dynamic>;
    final referenceElevation = (row[3] as num).toDouble();
    final referenceAzimuth = (row[4] as num).toDouble();
    final sun = localSunPosition(
      DateTime.parse(row[0] as String),
      Coordinates(
        latitude: (row[1] as num).toDouble(),
        longitude: (row[2] as num).toDouble(),
      ),
    );
    final elevationError = (sun.elevation - referenceElevation).abs();
    final azimuthError = (((sun.azimuth - referenceAzimuth + 180) % 360) - 180)
        .abs();

    final cosine =
        math.sin(sun.elevation * rad) * math.sin(referenceElevation * rad) +
        math.cos(sun.elevation * rad) *
            math.cos(referenceElevation * rad) *
            math.cos((sun.azimuth - referenceAzimuth) * rad);
    final directionError = math.acos(cosine.clamp(-1, 1)) / rad;
    maxElevation = math.max(maxElevation, elevationError);
    maxAzimuth = math.max(maxAzimuth, azimuthError);
    if (directionError > maxDirection) {
      maxDirection = directionError;
      worst = row;
    }
    if (referenceElevation.abs() < 1) nearHorizon++;
    if ((sun.elevation > 0) != (referenceElevation > 0)) {
      horizonDifferences++;
      if (referenceElevation.abs() >= 1) outsideHorizonBandDifferences++;
    }
  }
  return {
    'cases': (reference['cases'] as List).length,
    'maxElevationDifferenceDegrees': maxElevation,
    'maxAzimuthDifferenceDegrees': maxAzimuth,
    'maxDirectionDifferenceDegrees': maxDirection,
    'geometricHorizonSignDifferences': horizonDifferences,
    'signDifferencesOutsideOneDegreeHorizonBand': outsideHorizonBandDifferences,
    'referenceCasesWithinOneDegreeOfHorizon': nearHorizon,
    'worstDirectionReferenceCase': worst!,
    'scope': 'Numerical sun geometry; not measured shade accuracy.',
  };
}

void main(List<String> args) {
  if (args.length > 1) {
    throw const FormatException(
      'Usage: check_solar_reference.dart [fixture.json]',
    );
  }
  final file = args.isEmpty
      ? File.fromUri(
          Platform.script.resolve('../test/fixtures/solar_reference.json'),
        )
      : File(args.single);
  final reference = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final result = compareSolarReference(reference);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));

  if ((result['maxDirectionDifferenceDegrees'] as double) > 1 ||
      (result['maxElevationDifferenceDegrees'] as double) > 1 ||
      (result['maxAzimuthDifferenceDegrees'] as double) > 1 ||
      result['signDifferencesOutsideOneDegreeHorizonBand'] != 0) {
    exitCode = 1;
  }
}
