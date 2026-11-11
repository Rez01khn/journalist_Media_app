import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/screens/drafts_screen.dart';
import 'package:journalist_app_1/screens/submit_news_screen.dart';

void main() {
  late MockDraftRepository testRepo;

  setUp(() {
    testRepo = MockDraftRepository();
  });

  testWidgets('SubmitNewsScreen saves draft and updates state',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          draftRepositoryProvider.overrideWithValue(testRepo),
        ],
        child: const MaterialApp(
          home: SubmitNewsScreen(),
        ),
      ),
    );
    await tester.pump();

    // Type headline, location, and description
    await tester.enterText(
        find.byType(TextFormField).at(0), 'Breaking News from Dhaka');
    await tester.enterText(find.byType(TextFormField).at(1), 'Motijheel');
    await tester.enterText(
        find.byType(TextFormField).at(2), 'Details of the incident on the ground');
    await tester.pump();

    // Ensure Save Draft is visible and tap it
    await tester.ensureVisible(find.text('Save Draft'));
    await tester.tap(find.text('Save Draft'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // Verify it saved in the repository
    final drafts = await testRepo.getAllDrafts(reporterId: 'user-001');
    expect(drafts.any((d) => d.headline == 'Breaking News from Dhaka'), isTrue);
  });

  testWidgets('DraftsScreen displays saved drafts and allows deleting',
      (WidgetTester tester) async {
    // Clear initial mock drafts so only our target draft exists
    final initialDrafts = List.of(await testRepo.getAllDrafts(reporterId: 'user-001'));
    for (final d in initialDrafts) {
      await testRepo.deleteDraft(d.id);
    }

    await testRepo.saveDraft(
      NewsDraft(
        id: 'draft-test-1',
        reporterId: 'user-001',
        headline: 'Test Seeded Draft',
        category: 'Politics',
        location: 'Gulshan',
        incidentDetails: 'Seeded incident details',
        lastSavedAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          draftRepositoryProvider.overrideWithValue(testRepo),
        ],
        child: const MaterialApp(
          home: DraftsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify draft item is displayed
    expect(find.text('Test Seeded Draft'), findsOneWidget);
    expect(find.text('POLITICS'), findsOneWidget);
    expect(find.text('Gulshan'), findsOneWidget);

    // Tap delete button
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify confirmation dialog appears
    expect(find.text('Delete Draft?'), findsOneWidget);

    // Tap confirm delete
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Verify draft is deleted
    final remaining = await testRepo.getAllDrafts(reporterId: 'user-001');
    expect(remaining.isEmpty, isTrue);
    expect(find.text('No Saved Drafts'), findsOneWidget);
  });
}
