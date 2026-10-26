import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/shade_route/presentation/shade_model_preview.dart';
import 'package:heatwatch/features/shade_route/services/shade_route_service.dart';

class _FakeShadeRouteService extends ShadeRouteService {
  _FakeShadeRouteService(this.load);

  final Future<Map<String, dynamic>> Function(ShadeRouteTrip) load;

  @override
  Future<Map<String, dynamic>> getDemoRoutes(ShadeRouteTrip trip) => load(trip);
}

Future<Map<String, dynamic>> _showPreview(
  WidgetTester tester,
  _FakeShadeRouteService service, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final assetText = await tester.runAsync(
    () => rootBundle.loadString('assets/shade_demo.json'),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: SingleChildScrollView(child: ShadeModelPreview(service: service)),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Could not load the sample estimate.'), findsNothing);
  expect(find.byType(LinearProgressIndicator), findsNothing);
  expect(find.text('Route 1'), findsOneWidget);
  return jsonDecode(assetText!) as Map<String, dynamic>;
}

void main() {
  testWidgets('only a selected saved destination can be sent', (tester) async {
    var calls = 0;
    await _showPreview(
      tester,
      _FakeShadeRouteService((_) async {
        calls++;
        throw StateError('Should not be called');
      }),
    );
    final field = find.byKey(const Key('demo_destination_field'));
    final button = find.widgetWithText(
      OutlinedButton,
      'Send saved trip to local backend',
    );
    await tester.enterText(field, 'Other city');
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.text('Route 1'), findsNothing);
    expect(calls, 0);

    await tester.enterText(field, 'Demo');
    await tester.pumpAndSettle();
    final suggestion = find.byKey(const Key('demo_destination_suggestion'));
    await tester.ensureVisible(suggestion);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('loading hides stale routes and success restores them', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final sample = await _showPreview(
      tester,
      _FakeShadeRouteService((trip) {
        expect(trip.origin.latitude, 36.18998);
        return pending.future;
      }),
    );
    final button = find.widgetWithText(
      OutlinedButton,
      'Send saved trip to local backend',
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Checking saved trip…'), findsOneWidget);
    expect(find.text('Route 1'), findsNothing);

    pending.complete(sample);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Confirmed: saved trip matched'),
      findsOneWidget,
    );
    expect(find.text('Route 1'), findsOneWidget);
  });

  final failures = {
    ShadeRouteFailureKind.invalidTrip:
        'This trip is not available in the saved demo.',
    ShadeRouteFailureKind.noRoutes:
        'No walking routes were returned for this trip.',
    ShadeRouteFailureKind.outsideBuildingCoverage:
        'Building data does not cover this trip area.',
    ShadeRouteFailureKind.unavailable: 'Could not reach the local demo.',
    ShadeRouteFailureKind.invalidResponse:
        'The local backend returned incomplete route data.',
  };
  for (final failure in failures.entries) {
    testWidgets('${failure.key} shows a retryable route failure', (
      tester,
    ) async {
      await _showPreview(
        tester,
        _FakeShadeRouteService((_) async {
          throw ShadeRouteFailure(failure.key);
        }),
      );
      final button = find.widgetWithText(
        OutlinedButton,
        'Send saved trip to local backend',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining(failure.value), findsOneWidget);
      expect(find.text('Route 1'), findsNothing);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    });
  }

  testWidgets('retry restores routes after a local no-route failure', (
    tester,
  ) async {
    var attempts = 0;
    late Map<String, dynamic> sample;
    sample = await _showPreview(
      tester,
      _FakeShadeRouteService((_) async {
        attempts++;
        if (attempts == 1) {
          throw const ShadeRouteFailure(ShadeRouteFailureKind.noRoutes);
        }
        return sample;
      }),
    );
    final button = find.widgetWithText(
      OutlinedButton,
      'Send saved trip to local backend',
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Route 1'), findsNothing);
    expect(find.textContaining('No walking routes'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Route 1'), findsOneWidget);
    expect(
      find.textContaining('Confirmed: saved trip matched'),
      findsOneWidget,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('malformed backend route is hidden on $platform', (
      tester,
    ) async {
      final sample = await _showPreview(
        tester,
        _FakeShadeRouteService(
          (_) async => {
            'sampleOnly': true,
            'routes': [
              {'id': 'broken', 'durationSeconds': -1},
            ],
            'choices': {'fastest': 'broken'},
            'timeZoneId': 'America/Los_Angeles',
            'destination': {'label': 'Demo destination'},
            'origin': {'latitude': 34.0, 'longitude': -118.0},
            'departureTime': '2026-06-21T16:00:00Z',
          },
        ),
        platform: platform,
      );
      expect(sample['sampleOnly'], true);
      await tester.ensureVisible(find.text('Send saved trip to local backend'));
      await tester.tap(find.text('Send saved trip to local backend'));
      await tester.pumpAndSettle();
      expect(find.textContaining('incomplete route data'), findsOneWidget);
      expect(find.text('Route 1'), findsNothing);
    });
  }
}
