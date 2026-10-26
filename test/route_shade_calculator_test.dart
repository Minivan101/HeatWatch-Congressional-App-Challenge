import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/local_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_calculator.dart';
import 'package:heatwatch/features/shade_route/services/route_shade_repository.dart';
import 'package:heatwatch/features/shade_route/services/route_preference_selector.dart';
import 'package:heatwatch/core/settings/route_preference.dart';

const center = Coordinates(latitude: 36.195, longitude: -115.285);
Coordinates point(double east, double north) => Coordinates(
  latitude: center.latitude + north / 111195,
  longitude: center.longitude + east / 89700,
);
WalkingGeometry walk({double seconds = 600}) => WalkingGeometry(
  points: [point(-40, 0), point(40, 0)],
  durationSeconds: seconds,
  sourceUrl: 'https://example.com/test-only',
  accessReviewed: false,
);
RouteShadeData fixture({int canopy = 0, List<dynamic> buildings = const []}) {
  final p = shadeProject(center);
  final x = (p.x / 2560).floor(), y = (p.y / 2560).floor();
  return RouteShadeData(
    {
      'schemaVersion': 1,
      'crs': 'EPSG:3857',
      'cellMeters': 5,
      'tilePixels': 512,
      'bounds': {
        'south': 36.04,
        'north': 36.34,
        'west': -115.38,
        'east': -115.04,
      },
      'coverageGaps': [],
    },
    {
      '${x}_$y': Uint8List.fromList(
        GZipEncoder().encode(utf8.encode(jsonEncode(buildings))),
      ),
    },
    {
      for (var ox = -1; ox <= 1; ox++)
        for (var oy = -1; oy <= 1; oy++)
          '${x + ox}_${y + oy}': Uint8List.fromList(
            GZipEncoder().encode(
              Uint8List(512 * 512)..fillRange(0, 512 * 512, canopy),
            ),
          ),
    },
  );
}

List<dynamic> obstacle(
  double? height,
  double east,
  double north, {
  bool hole = false,
}) {
  List<List<double>> ring(double half) => [
    point(east - half, north - half),
    point(east + half, north - half),
    point(east + half, north + half),
    point(east - half, north + half),
  ].map((p) => [p.longitude, p.latitude]).toList();
  return [
    height,
    [ring(15), if (hole) ring(10)],
    .9,
  ];
}

class FileAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  test('the shadiest mapped corridor can change with departure time', () {
    final data = fixture(buildings: [obstacle(35, 0, 0)]);
    WalkingGeometry corridor(double side) => WalkingGeometry(
      points: [
        point(0, -60),
        point(side * 28, -22),
        point(side * 28, 22),
        point(0, 60),
      ],
      durationSeconds: 600,
      sourceUrl: 'https://example.com/test-only',
      accessReviewed: false,
    );
    int choice(DateTime departure) {
      final routes = [corridor(-1), corridor(1)];
      final metrics = [
        for (final route in routes)
          RoutePreferenceMetric(
            route.durationSeconds,
            timeTotals:
                calculateRouteShade(route, departure, data)['timeTotals']
                    as Map,
          ),
      ];
      return selectPreferredRoute(RoutePreference.mostShade, metrics).index;
    }

    expect(choice(DateTime.utc(2026, 6, 21, 16)), 0);
    expect(choice(DateTime.utc(2026, 6, 21, 23)), 1);
  });
  test('stationary timed segments retain exposure without adding distance', () {
    final result = calculateRouteShade(
      WalkingGeometry(
        points: [point(-40, 0), point(-40, 0), point(40, 0)],
        durationSeconds: 600,
        segmentSeconds: [500, 100],
        sourceUrl: 'https://example.com/test-only',
        accessReviewed: false,
      ),
      DateTime.parse('2026-06-21T20:00:00Z'),
      fixture(),
    );
    expect((result['timeTotals'] as Map)['open'], closeTo(600, .001));
    expect((result['totals'] as Map)['open'], closeTo(80, .3));
    expect(result['timingModel'], 'provider-segment-proportions');
  });

  test('provider segment timing changes exposure and still partitions total trip seconds', () {
    final at = DateTime.parse('2026-06-21T15:00:00Z');
    final sun = localSunPosition(at, center);
    final d = fixture(
      buildings: [
        obstacle(
          10,
          35 * math.sin(sun.azimuth * math.pi / 180),
          35 * math.cos(sun.azimuth * math.pi / 180),
        ),
      ],
    );
    Map<String, dynamic> run(List<double> weights) => calculateRouteShade(
      WalkingGeometry(
        points: [point(-40, 0), point(0, 0), point(15, 0)],
        durationSeconds: 1000,
        segmentSeconds: weights,
        sourceUrl: 'https://example.com/test-only',
        accessReviewed: false,
      ),
      at,
      d,
    );
    final a = run([9, 1]), b = run([1, 9]);
    for (final r in [a, b]) {
      expect(
        (r['timeTotals'] as Map).values.fold<double>(
          0,
          (s, v) => s + (v as double),
        ),
        closeTo(1000, .001),
      );
      expect(r['timingModel'], 'provider-segment-proportions');
    }
    expect(
      ((a['timeTotals'] as Map)['open'] as double) -
          ((b['timeTotals'] as Map)['open'] as double),
      greaterThan(20),
    );
  });
  test(
    'segment timing validates shape and scales with a chosen trip duration',
    () {
      const g = WalkingGeometry(
        points: [center, center, center],
        durationSeconds: 600,
        segmentSeconds: [9, 1],
        sourceUrl: 'https://example.com/test-only',
        accessReviewed: false,
      );
      expect(g.durationsFor([100, 100]), [540, 60]);
      expect(() => g.durationsFor([100]), throwsFormatException);
    },
  );
  test('building rays, holes, overlap and missing heights preserve classifications', () {
    final at = DateTime.parse('2026-06-21T15:00:00Z');
    final sun = localSunPosition(at, center);
    final east = 35 * math.sin(sun.azimuth * math.pi / 180),
        north = 35 * math.cos(sun.azimuth * math.pi / 180);
    final building = obstacle(80, east, north);
    final d = fixture(buildings: [building]);
    final result = calculateRouteShade(walk(), at, d);
    expect(result['buildingShade'], greaterThan(0));
    final overlap = calculateRouteShade(
      walk(),
      at,
      fixture(canopy: 10, buildings: [building]),
    );
    expect(overlap['shade'], closeTo(overlap['coverage'] as double, 1e-6));
    expect(
      (overlap['buildingShade'] as double) + (overlap['canopyShade'] as double),
      closeTo(overlap['shade'] as double, 1e-6),
    );
    final unknown = calculateRouteShade(
      walk(),
      at,
      fixture(buildings: [obstacle(null, east, north)]),
    );
    expect((unknown['totals'] as Map)['unknown'], greaterThan(0));
    final inSolid = calculateRouteShade(
      walk(),
      at,
      fixture(buildings: [obstacle(1, 0, 0)]),
    );
    final withCourtyard = calculateRouteShade(
      walk(),
      at,
      fixture(buildings: [obstacle(1, 0, 0, hole: true)]),
    );
    expect(
      (withCourtyard['totals'] as Map)['unknown'],
      lessThan((inSolid['totals'] as Map)['unknown'] as num),
    );
  });
  test('canopy mask stays unknown, valid zero means no modeled canopy, night separate', () {
    final at = DateTime.parse('2026-06-21T20:00:00Z');
    final empty = calculateRouteShade(walk(), at, fixture());
    expect(empty['shade'], 0);
    expect(empty['coverage'], 1);
    final missing = calculateRouteShade(walk(), at, fixture(canopy: 255));
    expect(missing['shade'], null);
    expect(missing['coverage'], 0);
    final trees = calculateRouteShade(walk(), at, fixture(canopy: 10));
    expect(trees['canopyShade'], 1);
    final night = calculateRouteShade(
      walk(),
      DateTime.parse('2026-06-21T08:00:00Z'),
      fixture(canopy: 10),
    );
    expect(night['shade'], null);
    expect(night['night'], night['distance']);
  });
  test('trip duration moves sample instants through sunset, totals partition distance', () {
    final at = DateTime.parse('2026-06-22T02:40:00Z');
    final short = calculateRouteShade(
      walk(seconds: 60),
      at,
      fixture(canopy: 10),
    );
    final long = calculateRouteShade(
      walk(seconds: 3600),
      at,
      fixture(canopy: 10),
    );
    expect(long['night'], greaterThan(short['night'] as double));
    final sum = (long['totals'] as Map).values.cast<double>().reduce(
      (a, b) => a + b,
    );
    expect(sum, closeTo(long['distance'] as double, 1e-6));
    expect(
      DateTime.parse(long['arrival'] as String).difference(at).inSeconds,
      3600,
    );
  });
  test(
    'out-of-area samples and corrupt source data do not produce invented shade',
    () {
      final r = WalkingGeometry(
        points: [
          const Coordinates(latitude: 36.345, longitude: -115.285),
          const Coordinates(latitude: 36.346, longitude: -115.285),
        ],
        durationSeconds: 300,
        sourceUrl: 'https://example.com/test-only',
        accessReviewed: false,
      );
      final result = calculateRouteShade(
        r,
        DateTime.parse('2026-06-21T20:00:00Z'),
        fixture(canopy: 10),
      );
      expect(result['shade'], null);
      expect(result['coverage'], 0);
      expect(
        () => fixture(buildings: [obstacle(-1, 0, 0)]),
        throwsFormatException,
      );
    },
  );
  test('packaged real Las Vegas data calculates sourced walking path at multiple times', () async {
    final raw = jsonDecode(
      File('docs/research/vegas-foot-route-2026-10-05.json').readAsStringSync(),
    );
    final provider = raw['routes'][0];
    final route = WalkingGeometry(
      points: (provider['geometry']['coordinates'] as List)
          .map(
            (p) => Coordinates(
              latitude: (p[1] as num).toDouble(),
              longitude: (p[0] as num).toDouble(),
            ),
          )
          .toList(),
      durationSeconds: (provider['duration'] as num).toDouble(),
      sourceUrl: 'https://routing.openstreetmap.de/about.html',
      accessReviewed: false,
    );
    final repository = RouteShadeRepository(bundle: FileAssets());
    final morning = await repository.calculate(
      route,
      DateTime.parse('2026-06-21T15:00:00Z'),
    );
    final noon = await repository.calculate(
      route,
      DateTime.parse('2026-06-21T20:00:00Z'),
    );
    final night = await repository.calculate(
      route,
      DateTime.parse('2026-06-21T08:00:00Z'),
    );

    final weighted = await repository.calculate(
      WalkingGeometry(
        points: route.points,
        durationSeconds: route.durationSeconds,
        segmentSeconds: List.generate(
          route.points.length - 1,
          (i) => i < route.points.length / 2 ? 9.0 : 1.0,
        ),
        sourceUrl: 'https://example.com/test-only-timing',
        accessReviewed: false,
      ),
      DateTime.parse('2026-06-21T15:00:00Z'),
    );
    expect(weighted['timingModel'], 'provider-segment-proportions');
    expect(
      (weighted['timeTotals'] as Map).values.fold<double>(
        0,
        (sum, value) => sum + (value as num).toDouble(),
      ),
      closeTo(route.durationSeconds, .01),
    );
    expect(morning['heights'], greaterThan(500));
    expect(morning['shade'], isNotNull);
    expect(noon['shade'], isNotNull);
    expect(morning['shade'], isNot(noon['shade']));
    expect(night['shade'], null);
    expect(night['night'], closeTo(night['distance'] as double, .001));
    expect(morning['segments'], isNotEmpty);
    final expectedStart = localSunPosition(
      DateTime.parse('2026-06-21T15:00:00Z'),
      route.points.first,
    );
    expect(
      (morning['sunAtDeparture'] as Map)['elevation'],
      expectedStart.elevation,
    );
    final arrival = DateTime.parse(morning['arrival'] as String);
    expect(
      (morning['sunAtArrival'] as Map)['azimuth'],
      localSunPosition(arrival, route.points.last).azimuth,
    );

    File('${Directory.systemTemp.path}/heatwatch-route-audit.json')
        .writeAsStringSync(
          jsonEncode({
            'routeSource': route.sourceUrl,
            'morning': {
              for (final key in [
                'distance',
                'duration',
                'shade',
                'coverage',
                'departure',
                'arrival',
                'sunAtDeparture',
                'sunAtArrival',
                'totals',
              ])
                key: morning[key],
            },
            'noon': {
              for (final key in [
                'shade',
                'coverage',
                'sunAtDeparture',
                'sunAtArrival',
              ])
                key: noon[key],
            },
            'night': {
              for (final key in ['shade', 'night', 'distance']) key: night[key],
            },
          }),
        );
  });
}
