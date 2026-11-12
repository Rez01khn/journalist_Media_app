import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/providers/auth_provider.dart';
import 'package:journalist_app_1/providers/google_drive_provider.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/screens/profile_screen.dart';

import 'login_integration_test.dart' show InMemorySecureTokenStorage;

class _AuthenticatedTestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      status: AuthStatus.authenticated,
      session: AuthSession(
        accessToken: 'test_token',
        user: AuthUser(
          id: 4,
          uuid: 'uuid-rep-001',
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
}

void main() {
  testWidgets(
    'ProfileScreen displays Google Drive Storage section and connects',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockRepo = MockGoogleDriveRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureTokenStorageProvider.overrideWithValue(
              InMemorySecureTokenStorage(),
            ),
            authStateProvider.overrideWith(_AuthenticatedTestAuthNotifier.new),
            googleDriveRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Google Drive Storage card is displayed
      expect(find.text('Google Drive Storage'), findsOneWidget);
      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.text('Connect Google Drive'), findsOneWidget);

      // Tap "Connect Google Drive" button
      await tester.tap(find.text('Connect Google Drive'));
      await tester.pumpAndSettle();

      // Verify status updates to Connected
      expect(find.text('Connected'), findsWidgets);
      expect(find.text('Journalist App Dispatches'), findsOneWidget);
      expect(find.text('View Files'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      // Open "View Files" bottom sheet
      await tester.tap(find.text('View Files'));
      await tester.pumpAndSettle();

      expect(find.text('Google Drive Dispatches'), findsOneWidget);
      expect(find.text('Upload Test Dispatch'), findsOneWidget);
      expect(find.text('No dispatches uploaded yet.'), findsOneWidget);

      // Tap "Upload Test Dispatch"
      await tester.tap(find.text('Upload Test Dispatch'));
      await tester.pumpAndSettle();

      // Verify the file was uploaded and listed in the modal
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Verify 1 synced item count is shown on the card
      expect(find.text('1 field dispatches'), findsOneWidget);

      // Tap Disconnect
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      // Verify reset to Not Connected
      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.text('Connect Google Drive'), findsOneWidget);
    },
  );
}
