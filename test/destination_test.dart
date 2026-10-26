import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/shade_route/presentation/shade_model_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await rootBundle.loadString('assets/shade_demo.json');
  });
  testWidgets('demo destination must be selected before showing routes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ShadeModelPreview()),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('demo_destination_field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Other city');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No saved demo destination matches'),
      findsOneWidget,
    );
    expect(find.text('Route 1'), findsNothing);

    await tester.enterText(field, 'Demo');
    await tester.pumpAndSettle();
    expect(find.text('Saved demo destination'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Demo destination'));
    await tester.tap(find.text('Demo destination'));
    await tester.pumpAndSettle();
    expect(
      find.text('Selected demo destination: Demo destination'),
      findsOneWidget,
    );
    expect(find.text('Route 1'), findsOneWidget);
  });
}
