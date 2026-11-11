import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/main.dart';

void main() {
  testWidgets('Bottom navigation smoke and tab switching test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: JournalistApp(),
      ),
    );

    // Verify all four bottom navigation destinations exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Submit News'), findsWidgets);
    expect(find.text('My News'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Initial tab should show Dashboard
    expect(find.text('Journalist Dashboard'), findsOneWidget);

    // Tap 'Profile' tab
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();

    // Verify Profile screen is displayed
    expect(find.text('Reporter Profile'), findsOneWidget);
    expect(find.text('Rezwan Karim'), findsOneWidget);

    // Tap 'Submit News' tab
    await tester.tap(find.byIcon(Icons.post_add_outlined));
    await tester.pumpAndSettle();

    // Verify Submit News screen is displayed
    expect(find.text('Field Reporting Desk'), findsOneWidget);

    // Tap 'My News' tab
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    // Verify My News screen is displayed
    expect(find.text('REP-101'), findsOneWidget);
  });
}
