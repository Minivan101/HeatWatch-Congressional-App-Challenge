import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/features/shade_route/services/city_trip_service.dart';
import 'package:heatwatch/features/shade_route/services/walking_navigation.dart';

import 'support/recorded_vegas_walk.dart';

void main() {
  test('native replay preserves every coordinate of the published source', () {
    final original = CityTripService.parseAlternatives(
      jsonDecode(
        File('docs/research/vegas-long-foot-route-2026-10-10.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    final service = RecordedWalkingService();
    addTearDown(service.client.close);
    expect(service.recorded, hasLength(original.length));
    for (var i = 0; i < original.length; i++) {
      final a = service.recorded[i], b = original[i];
      expect(a.distanceMeters, b.distanceMeters);
      expect(a.geometry.durationSeconds, b.geometry.durationSeconds);
      expect(a.geometry.segmentSeconds, isNull);
      expect(a.steps.length, b.steps.length);
      expect(
        a.geometry.points.map((p) => [p.latitude, p.longitude]).toList(),
        b.geometry.points.map((p) => [p.latitude, p.longitude]).toList(),
      );
    }
  });
  test(
    'replay rejects unknown corridors and recovers from an injected outage',
    () async {
      final service = RecordedWalkingService();
      addTearDown(service.client.close);
      final route = service.recorded.first;
      final start = route.geometry.points.first,
          end = route.geometry.points.last;
      service.failNext = true;
      await expectLater(
        service.walkAlternatives(start, end),
        throwsFormatException,
      );
      final recovered = await service.walkAlternatives(start, end);
      expect(recovered, isNotEmpty);
      await expectLater(
        service.walkAlternatives(
          const Coordinates(latitude: 36.4, longitude: -115.45),
          end,
        ),
        throwsFormatException,
      );
      await expectLater(
        service.walkAlternatives(start, end, via: [start]),
        throwsFormatException,
      );
      final later = route.geometry.points[20];
      final trimmed = await service.walkAlternatives(later, end);
      expect(trimmed.first.distanceMeters, lessThan(route.distanceMeters));
      expect(
        walkingDistance(trimmed.first.geometry.points.first, later),
        lessThan(1),
      );
    },
  );
}
