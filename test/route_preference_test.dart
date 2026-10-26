import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/settings/route_preference.dart';
import 'package:heatwatch/features/shade_route/services/route_preference_selector.dart';

void main() {
  test('most shade ranks actual segment-time shaded share', () {
    const pool = [
      RoutePreferenceMetric(
        600,
        shade: .8,
        coverage: 1,
        timeTotals: {
          'building': 100.0,
          'canopy': 0.0,
          'open': 500.0,
          'unknown': 0.0,
          'night': 0.0,
        },
      ),
      RoutePreferenceMetric(
        660,
        shade: .2,
        coverage: 1,
        timeTotals: {
          'building': 500.0,
          'canopy': 0.0,
          'open': 160.0,
          'unknown': 0.0,
          'night': 0.0,
        },
      ),
    ];
    expect(selectPreferredRoute(RoutePreference.mostShade, pool).index, 1);
    expect(pool.first.sunSeconds, 500);
    expect(pool.last.shadedSeconds, 500);
  });
  test(
    'low shade and sparse data use time availability with segment timing',
    () {
      const low = [
        RoutePreferenceMetric(
          600,
          shade: .9,
          coverage: 1,
          timeTotals: {
            'building': 20.0,
            'canopy': 0.0,
            'open': 580.0,
            'unknown': 0.0,
            'night': 0.0,
          },
        ),
        RoutePreferenceMetric(
          660,
          shade: .9,
          coverage: 1,
          timeTotals: {
            'building': 10.0,
            'canopy': 0.0,
            'open': 650.0,
            'unknown': 0.0,
            'night': 0.0,
          },
        ),
      ];
      expect(selectPreferredRoute(RoutePreference.mostShade, low).index, 0);
      expect(
        selectPreferredRoute(RoutePreference.mostShade, low).littleShade,
        false,
      );
      const unknown = RoutePreferenceMetric(
        600,
        shade: .5,
        coverage: .99,
        timeTotals: {
          'building': 300.0,
          'canopy': 0.0,
          'open': 100.0,
          'unknown': 200.0,
          'night': 0.0,
        },
      );
      expect(unknown.comparable, false);
      expect(unknown.unknownSeconds, 200);
      expect(unknown.sunSeconds, 300);
      const corrupt = RoutePreferenceMetric(
        600,
        shade: .5,
        coverage: 1,
        timeTotals: {'building': 600.0},
      );
      expect(corrupt.comparable, false);
    },
  );
  test(
    'unknown exposure stays explicit and impossible shade coverage is rejected',
    () {
      const metric = RoutePreferenceMetric(600, shade: .3, coverage: .95);
      expect(metric.knownSunSeconds, closeTo(390, .001));
      expect(metric.unknownSeconds, closeTo(30, .001));
      expect(metric.sunSeconds, closeTo(420, .001));
      expect(
        const RoutePreferenceMetric(600, shade: .99, coverage: .9).comparable,
        false,
      );
    },
  );
  test('visible routes retain preference winners beyond the first three candidates', () {
    const pool = [
      RoutePreferenceMetric(600, shade: .1, coverage: 1),
      RoutePreferenceMetric(700, shade: .2, coverage: 1),
      RoutePreferenceMetric(720, shade: .8, coverage: 1),
      RoutePreferenceMetric(900, shade: .4, coverage: 1),
      RoutePreferenceMetric(1100, shade: .99, coverage: 1),
    ];
    expect(representativeRouteIndices(pool), [0, 2, 4]);
    expect(representativeRouteIndices(pool.take(1).toList()), [0]);
    expect(representativeRouteIndices([]), isEmpty);
  });
  const candidates = [
    RoutePreferenceMetric(600, shade: .1, coverage: 1),
    RoutePreferenceMetric(720, shade: .8, coverage: 1),
    RoutePreferenceMetric(900, shade: .95, coverage: 1),
  ];
  test('three choices rank shade, time and capped balance differently', () {
    expect(selectPreferredRoute(RoutePreference.fastest, candidates).index, 0);
    expect(selectPreferredRoute(RoutePreference.balanced, candidates).index, 1);
    expect(
      selectPreferredRoute(RoutePreference.mostShade, candidates).index,
      2,
    );
  });
  test('balance never allows more than 25 percent extra walking time', () {
    expect(
      selectPreferredRoute(RoutePreference.balanced, [
        const RoutePreferenceMetric(600, shade: 0, coverage: 1),
        const RoutePreferenceMetric(751, shade: 1, coverage: 1),
      ]).index,
      0,
    );
  });
  test('unknown and sparse daylight data do not masquerade as shade', () {
    for (final metric in [
      const RoutePreferenceMetric(720),
      const RoutePreferenceMetric(720, shade: .9, coverage: .7),
      const RoutePreferenceMetric(720, shade: double.nan, coverage: 1),
    ]) {
      final result = selectPreferredRoute(RoutePreference.mostShade, [
        candidates[0],
        metric,
      ]);
      expect(result.index, 0);
      expect(result.shadeUnavailable, true);
    }
  });
  test('one incomplete alternative does not hide two comparable routes', () {
    const pool = [
      RoutePreferenceMetric(600, shade: .1, coverage: 1),
      RoutePreferenceMetric(620, shade: .8, coverage: 1),
      RoutePreferenceMetric(610, shade: .9, coverage: .3),
    ];
    expect(selectPreferredRoute(RoutePreference.fastest, pool).index, 0);
    expect(selectPreferredRoute(RoutePreference.mostShade, pool).index, 1);
    expect(selectPreferredRoute(RoutePreference.balanced, pool).index, 1);
  });
  test(
    'fully nighttime routes use fastest without an unavailable comparison',
    () {
      const night = [
        RoutePreferenceMetric(720, daylight: 0),
        RoutePreferenceMetric(600, daylight: 0),
      ];
      expect(night.first.comparable, true);
      expect(night.first.sunSeconds, 0);
      expect(night.first.shadedSeconds, 0);
      expect(night.first.nightSeconds, 720);
      for (final mode in RoutePreference.values) {
        final choice = selectPreferredRoute(mode, night);
        expect(choice.index, 1);
        expect(choice.shadeUnavailable, false);
        expect(choice.littleShade, false);
      }
      final mixed = selectPreferredRoute(RoutePreference.mostShade, [
        candidates.first,
        const RoutePreferenceMetric(720, daylight: 0),
      ]);
      expect(mixed.index, 0);
      expect(mixed.shadeUnavailable, false);
    },
  );
  test(
    'night portions reduce sun time and exposure ties prefer faster travel',
    () {
      expect(
        selectPreferredRoute(RoutePreference.mostShade, [
          const RoutePreferenceMetric(600, shade: .4, coverage: 1),
          const RoutePreferenceMetric(
            720,
            shade: .8,
            coverage: 1,
            daylight: .3,
          ),
        ]).index,
        1,
      );
      expect(
        selectPreferredRoute(RoutePreference.mostShade, [
          const RoutePreferenceMetric(720, shade: .8, coverage: 1),
          const RoutePreferenceMetric(600, shade: .8, coverage: 1),
        ]).index,
        1,
      );
    },
  );
  test('most shade selects the highest shaded share', () {
    const routes = [
      RoutePreferenceMetric(600, shade: .4, coverage: 1),
      RoutePreferenceMetric(1200, shade: .65, coverage: 1),
    ];
    expect(routes[1].shadedSeconds, greaterThan(routes[0].shadedSeconds));
    expect(routes[0].sunSeconds, 360);
    expect(routes[1].sunSeconds, 420);
    expect(selectPreferredRoute(RoutePreference.mostShade, routes).index, 1);
  });
  test('small shade gains still count', () {
    const routes = [
      RoutePreferenceMetric(600, shade: .01, coverage: 1),
      RoutePreferenceMetric(620, shade: .09, coverage: 1),
    ];
    expect(routes[1].sunSeconds, lessThan(routes[0].sunSeconds));
    expect(selectPreferredRoute(RoutePreference.fastest, routes).index, 0);
    expect(selectPreferredRoute(RoutePreference.mostShade, routes).index, 1);
    expect(
      selectPreferredRoute(RoutePreference.mostShade, routes).littleShade,
      false,
    );
  });
  test('a candidate at low-shade boundary retains exposure comparison', () {
    final choice = selectPreferredRoute(RoutePreference.mostShade, [
      const RoutePreferenceMetric(600, shade: .01, coverage: 1),
      const RoutePreferenceMetric(620, shade: .10, coverage: 1),
    ]);
    expect(choice.index, 1);
    expect(choice.littleShade, false);
  });
}
