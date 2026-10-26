import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/presentation/heat_guard_page.dart';
import 'package:heatwatch/features/heat_guard/services/heat_guard_service.dart';

class _FakeHeatGuardService extends HeatGuardService {
  const _FakeHeatGuardService(this.load);

  final Future<Map<String, dynamic>> Function() load;

  @override
  Future<Map<String, dynamic>> getLocalExample() => load();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> openReport(WidgetTester tester) async {
  await reveal(tester, find.text('View example scenarios'));
  await tester.tap(find.text('View example scenarios'));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late Map<String, dynamic> data;
  setUpAll(() async {
    data = jsonDecode(
      await rootBundle.loadString('assets/heat_guard_scenarios.json'),
    ) as Map<String, dynamic>;
  });

  testWidgets(
    'fictional active alert appears before conditions with text and icon',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HeatGuardPage(scenarioLoader: () async => data)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No live weather or official alert check yet.'),
        findsOneWidget,
      );
      expect(find.textContaining('Example severe alert'), findsNothing);
      await openReport(tester);
      await reveal(tester, find.text('Example Heat Guard scenarios'));
      expect(
        find.textContaining('Fictional historical examples'),
        findsOneWidget,
      );
      expect(find.textContaining('Example severe alert'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('Example temperature'), findsOneWidget);
      expect(
        find.textContaining('Publisher website (not alert-specific)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('checked, unchecked, and stale scenarios stay distinct', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HeatGuardPage(scenarioLoader: () async => data)),
      ),
    );
    await tester.pumpAndSettle();
    await openReport(tester);
    await reveal(tester, find.text('Example Heat Guard scenarios'));
    await tester.ensureVisible(find.text('Checked: none'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checked: none'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('no heat alerts in this simulated check'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Not checked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not checked'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not checked in this example'), findsOneWidget);
    await tester.ensureVisible(find.text('Outdated'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outdated'));
    await tester.pumpAndSettle();
    expect(find.textContaining('example check is outdated'), findsOneWidget);
    expect(find.text('General preparation'), findsNothing);
  });

  testWidgets('loading and failure have a retry path', (tester) async {
    final first = Completer<Map<String, dynamic>>();
    var calls = 0;
    Future<Map<String, dynamic>> load() {
      calls++;
      return calls == 1 ? first.future : Future.value(data);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HeatGuardPage(scenarioLoader: load)),
      ),
    );
    await openReport(tester);
    await reveal(tester, find.text('Example Heat Guard scenarios'));
    await tester.pump();
    expect(find.text('Loading examples…'), findsOneWidget);
    first.completeError(StateError('local fixture unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Examples could not be loaded.'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry examples'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry examples'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Example severe alert'), findsOneWidget);
  });

  testWidgets('local Function example remains clearly fictional', (
    tester,
  ) async {
    var calls = 0;
    final service = _FakeHeatGuardService(() async {
      calls++;
      if (calls == 1) throw StateError('emulator unavailable');
      return {
        'sampleOnly': true,
        'exampleAsOf': data['exampleAsOf'],
        'scenario': (data['scenarios'] as Map)['active'],
      };
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeatGuardPage(
            scenarioLoader: () async => data,
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openReport(tester);
    await reveal(tester, find.text('Load local Heat Guard example'));
    await tester.tap(find.text('Load local Heat Guard example'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Local Function unavailable'), findsOneWidget);
    await reveal(tester, find.text('Load local Heat Guard example'));
    await tester.tap(find.text('Load local Heat Guard example'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No Weather API request was made'),
      findsOneWidget,
    );
    final localCard = find.ancestor(
      of: find.textContaining('Local Function responded'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: localCard,
        matching: find.textContaining('Example severe alert'),
      ),
      findsOneWidget,
    );
    expect(calls, 2);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('malformed scenario shows retry without weather advice on '
        '$platform', (tester) async {
      final invalid = Map<String, dynamic>.from(data);
      invalid['exampleAsOf'] = '2026-06-21T09:00:00';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: HeatGuardPage(scenarioLoader: () async => invalid),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openReport(tester);
      await reveal(tester, find.text('Example Heat Guard scenarios'));
      expect(find.text('Examples could not be loaded.'), findsOneWidget);
      expect(find.text('Retry examples'), findsOneWidget);
      expect(find.text('General preparation'), findsNothing);
    });
  }
}
