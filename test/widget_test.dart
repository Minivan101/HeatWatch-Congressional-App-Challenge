import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await rootBundle.loadString('data/cooling_centers/official_directory.json');
  });
  testWidgets('all three HeatWatch pages open from the navigation bar', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const HeatWatchApp(promptLocation: false, mapTilesEnabled: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });

    await tester.pump();
    expect(find.byKey(const ValueKey('home-conditions')), findsOneWidget);
    await tester.tap(find.text('ShadeMap'));
    await tester.pump();
    expect(find.text('Route options'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Find walking routes'),
      100,
      scrollable: find.byType(DraggableScrollableSheet).evaluate().isEmpty
          ? find.byType(Scrollable).first
          : find
                .descendant(
                  of: find.byType(DraggableScrollableSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
    );
    expect(find.text('Find walking routes'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.ac_unit));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    expect(find.text('A cooler place, closer to you.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '89119');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Cambridge');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Cambridge Recreation Center'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cambridge Recreation Center'), findsOneWidget);
    expect(find.text('Fictional Cafe'), findsNothing);

    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('home-conditions')), findsOneWidget);
    expect(find.text('View example scenarios'), findsNothing);
  });
}
