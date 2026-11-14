import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/main.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/providers/app_providers.dart';

class _AuthenticatedSmokeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      status: AuthStatus.authenticated,
      session: AuthSession(
        accessToken: 'smoke_test_token',
        user: AuthUser(
          id: 4,
          uuid: 'uuid-smoke-001',
          userCode: 'REP-2026-084',
          name: 'Rezwan Ahmed',
          email: 'reporter@newsdesk.local',
          role: PortalUserRole.reporter,
          designation: 'Staff Reporter',
          assignedArea: 'Dhaka Metro',
        ),
      ),
    );
  }

  @override
  Future<void> restoreSession() async {}
}

void main() {
  testWidgets('Bottom navigation smoke and tab switching test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_AuthenticatedSmokeAuthNotifier.new),
          newsListProvider(null).overrideWith((ref) async => [
                News(
                  id: '1',
                  trackingCode: 'REP-101',
                  reporterId: '4',
                  reporterName: 'Rezwan Ahmed',
                  headline: 'REP-101 Breaking Report',
                  incidentDetails: 'Detailed report contents here...',
                  category: 'Politics',
                  location: 'Dhaka Central',
                  status: NewsStatus.pending,
                  submittedAt: DateTime.now(),
                ),
              ]),
          newsStatusCountsProvider.overrideWith((ref) async => {
                NewsStatus.pending: 1,
              }),
        ],
        child: const JournalistApp(),
      ),
    );
    await tester.pumpAndSettle();

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

    // Verify Profile screen displays authenticated user
    expect(find.text('Reporter Profile'), findsOneWidget);
    expect(find.text('Rezwan Ahmed'), findsOneWidget);

    // Tap 'Submit News' tab
    await tester.tap(find.byIcon(Icons.post_add_outlined));
    await tester.pumpAndSettle();

    // Verify Submit News screen is displayed
    expect(find.text('Quick Field Capture'), findsOneWidget);

    // Tap 'My News' tab
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    // Verify My News screen is displayed
    expect(find.text('REP-101'), findsOneWidget);
  });
}
