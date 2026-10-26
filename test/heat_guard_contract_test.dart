import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/models/heat_guard_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'historical Heat Guard examples keep explicit source and dates',
    () async {
      final fixture = jsonDecode(
        await rootBundle.loadString('assets/heat_guard_scenarios.json'),
      ) as Map<String, dynamic>;
      expect(HeatGuardContract.examples(fixture)['sampleOnly'], true);
      expect(
        () => HeatGuardContract.examples({...fixture, 'sampleOnly': false}),
        throwsFormatException,
      );
      expect(
        () => HeatGuardContract.examples({
          ...fixture,
          'exampleAsOf': '2026-06-21T09:00:00',
        }),
        throwsFormatException,
      );
    },
  );

  test('unchecked alerts and ambiguous expiry fail closed', () {
    final now = DateTime.utc(2026, 11, 1, 9);
    final base = {
      'current': {
        'temperatureC': 30,
        'feelsLikeC': 32,
        'humidityPercent': 50,
        'uvIndex': 5,
      },
      'alertsChecked': true,
      'alerts': [
        {
          'title': 'Example',
          'severity': 'severe',
          'source': 'Agency',
          'sourceUrl': 'https://example.gov',
          'expiresAt': '2026-11-01T01:00:01-08:00',
        },
      ],
      'guidance': ['Example guidance'],
      'fetchedAt': '2026-11-01T01:59:59-07:00',
    };
    expect(HeatGuardContract.scenario(base, now)['alertsChecked'], true);
    expect(
      () => HeatGuardContract.scenario({...base, 'alertsChecked': false}, now),
      throwsFormatException,
    );
    final ambiguous = Map<String, dynamic>.from(base);
    ambiguous['alerts'] = [
      {...(base['alerts'] as List).first, 'expiresAt': '2026-11-01T01:00:00'},
    ];
    expect(
      () => HeatGuardContract.scenario(ambiguous, now),
      throwsFormatException,
    );
  });
}
