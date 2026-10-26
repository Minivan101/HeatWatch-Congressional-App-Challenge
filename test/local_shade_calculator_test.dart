import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';

const center = Coordinates(latitude: 36.195, longitude: -115.285);
Coordinates metric(double east, double north) => Coordinates(
  latitude: center.latitude + north / 111195,
  longitude: center.longitude + east / 89700,
);
Map<String, dynamic> building({
  double? height = 10,
  String source = 'height',
}) => {
  'footprint': [
    metric(10, -5),
    metric(20, -5),
    metric(20, 5),
    metric(10, 5),
  ].map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
  'heightMeters': height,
  'heightSource': source,
};
LocalShadeBuildings dataset(List<Map<String, dynamic>> buildings) =>
    LocalShadeBuildings({
      'schemaVersion': 1,
      'bounds': {
        'south': 36.18,
        'north': 36.21,
        'west': -115.30,
        'east': -115.27,
      },
      'buildings': buildings,
      'coverageGaps': [],
    });
WalkingGeometry route() => WalkingGeometry(
  points: [metric(-50, -20), metric(50, -20)],
  durationSeconds: 600,
  sourceUrl:
      'https://api.openrouteservice.org/v2/directions/foot-walking/geojson',
  accessReviewed: false,
);

void main() {
  test('NOAA numeric checkpoints use January 1 and leap-day year lengths', () {
    for (final reference in [
      ('2026-01-01T20:00:00Z', 30.654282756277865, 184.2277938569751),
      ('2024-02-29T20:00:00Z', 45.96812064310438, 182.13371643682592),
    ]) {
      final sun = localSunPosition(DateTime.parse(reference.$1), center);
      expect(sun.elevation, closeTo(reference.$2, 1e-8));
      expect(sun.azimuth, closeTo(reference.$3, 1e-8));
    }
  });
  test(
    'real extract preserves missing heights and has no fabricated routes',
    () {
      final data = LocalShadeBuildings(
        jsonDecode(
          File('data/buildings/pilot/buildings.json').readAsStringSync(),
        ),
      );
      expect(data.buildings.length, 2128);
      expect(data.explicitHeights, 0);
      expect(data.unknownHeights, 2127);
      expect(data.levelEstimates, 1);
      expect(
        jsonDecode(
          File('data/buildings/pilot/routes.json').readAsStringSync(),
        )['routes'],
        isEmpty,
      );
    },
  );
  test(
    'solar UTC instant is timezone independent and follows daily geometry',
    () {
      final morning = localSunPosition(
        DateTime.parse('2026-06-21T15:00:00Z'),
        center,
      );
      final noon = localSunPosition(
        DateTime.parse('2026-06-21T20:00:00Z'),
        center,
      );
      final afternoon = localSunPosition(
        DateTime.parse('2026-06-21T00:00:00Z'),
        center,
      );
      expect(noon.elevation, greaterThan(morning.elevation));
      expect(morning.azimuth, lessThan(180));
      expect(afternoon.azimuth, greaterThan(180));
      expect(
        localSunPosition(DateTime.parse('2026-06-21T13:00:00-07:00'), center),
        noon,
      );
    },
  );
  test('shadow points away from sun and excludes interior footprints', () {
    final footprint = [
      metric(10, -5),
      metric(20, -5),
      metric(20, 5),
      metric(10, 5),
    ];
    expect(buildingShadowContains(center, footprint, 20, 45, 90), isTrue);
    expect(buildingShadowContains(center, footprint, 20, 45, 270), isFalse);
    expect(
      buildingShadowContains(metric(15, 0), footprint, 20, 45, 90),
      isFalse,
    );
    expect(buildingShadowContains(center, footprint, 20, -1, 90), isFalse);
  });
  test(
    'unknown heights never become zero-shade percentages; distance weights sum',
    () {
      final result = const LocalShadeCalculator().calculate(
        route(),
        dataset([building(height: null, source: 'unknown')]),
        DateTime.parse('2026-06-21T20:00:00Z'),
      );
      expect(result.modeledShadeFraction, isNull);
      expect(result.daylightMeters, closeTo(result.distanceMeters, 0.001));
      expect(result.samples, greaterThan(9));
    },
  );
  test(
    'floor-based heights require explicit opt in; night has no shade ranking',
    () {
      final d = dataset([building(source: 'building:levels')]);
      final calculator = const LocalShadeCalculator();
      expect(
        calculator
            .calculate(route(), d, DateTime.parse('2026-06-21T20:00:00Z'))
            .modeledShadeFraction,
        isNull,
      );
      expect(
        calculator
            .calculate(
              route(),
              d,
              DateTime.parse('2026-06-21T20:00:00Z'),
              allowLevelEstimates: true,
            )
            .modeledShadeFraction,
        isNotNull,
      );
      final night = calculator.calculate(
        route(),
        d,
        DateTime.parse('2026-06-21T08:00:00Z'),
        allowLevelEstimates: true,
      );
      expect(night.modeledShadeFraction, isNull);
      expect(night.nightMeters, closeTo(night.distanceMeters, 0.001));
    },
  );
  test('buffered coverage and incomplete polygons refuse estimates', () {
    final d = dataset([]);
    expect(
      () => d.requireCoverage([
        const Coordinates(latitude: 36.1801, longitude: -115.285),
      ]),
      throwsFormatException,
    );
    d.data['coverageGaps'] = [
      {'bounds': null},
    ];
    expect(() => d.requireCoverage([center]), throwsFormatException);
  });
  test('driving GeoJSON is rejected as walking geometry', () {
    expect(
      () => WalkingGeometry.fromOrsFeature(
        {},
        profile: 'driving-car',
        accessReviewed: false,
      ),
      throwsFormatException,
    );
  });
}
