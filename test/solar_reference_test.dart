import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../scripts/check_solar_reference.dart';

void main() {
  test(
    'solar approximation stays within independent Las Vegas SPA envelope',
    () {
      final reference = jsonDecode(
        File('test/fixtures/solar_reference.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(reference['cases'], hasLength(3170));
      expect(
        reference['sourceSha256'],
        'b7858858d9dceac4c9ad98a0a0f56cefba9e2bf972c63e5c1c243e74888e3dfc',
      );
      final result = compareSolarReference(reference);
      expect(result['maxDirectionDifferenceDegrees'], lessThan(1));
      expect(result['maxElevationDifferenceDegrees'], lessThan(1));
      expect(result['maxAzimuthDifferenceDegrees'], lessThan(1));
      expect(result['signDifferencesOutsideOneDegreeHorizonBand'], 0);

      expect(
        result['referenceCasesWithinOneDegreeOfHorizon'],
        greaterThan(200),
      );
    },
  );
}
