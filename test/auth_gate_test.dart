import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/main.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';

import 'login_integration_test.dart' show InMemorySecureTokenStorage;

class _DelayedSessionStorage extends InMemorySecureTokenStorage {
  final Completer<AuthSession?> readCompleter = Completer<AuthSession?>();

  @override
  Future<AuthSession?> readSession() => readCompleter.future;
}

AuthSession _sessionForRole(PortalUserRole role) {
  return AuthSession(
    accessToken: '1|jrn_${role.apiValue}_token',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    abilities: const ['*'],
    user: AuthUser(
      id: 10,
      uuid: 'uuid-${role.apiValue}',
      userCode: 'USR-2026-${role.apiValue.toUpperCase()}',
      name: '${role.displayLabel} User',
      email: '${role.apiValue}@newsdesk.local',
      role: role,
      designation: role.displayLabel,
      assignedArea: 'Dhaka',
    ),
  );
}

void main() {
  group('TASK 06.8 — Authentication Gate Widget & State Tests', () {
    testWidgets('shows loading state while checking saved session then transitions to LoginScreen', (
      WidgetTester tester,
    ) async {
      final delayedStorage = _DelayedSessionStorage();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureTokenStorageProvider.overrideWithValue(delayedStorage),
          ],
          child: const JournalistApp(),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('auth_gate_loading')), findsOneWidget);
      expect(find.text('Checking session...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Journalist Dashboard'), findsNothing);

      delayedStorage.readCompleter.complete(null);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth_gate_loading')), findsNothing);
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.text('Journalist Dashboard'), findsNothing);
    });

    testWidgets('restores authenticated sessions for all four roles on startup', (
      WidgetTester tester,
    ) async {
      for (final role in PortalUserRole.values) {
        final storage = InMemorySecureTokenStorage();
        final session = _sessionForRole(role);
        await storage.saveSession(session);
        final mockClient = MockClient((request) async {
          if (request.url.path.endsWith('/auth/session-check')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'message': 'Authenticated session is active.',
                'data': session.user.toJson(),
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'success': false, 'message': 'Not found'}),
            404,
          );
        });

        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(role),
            overrides: [
              secureTokenStorageProvider.overrideWithValue(storage),
              authApiServiceProvider.overrideWithValue(
                AuthApiService(
                  client: mockClient,
                  baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
                ),
              ),
            ],
            child: const JournalistApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Journalist Dashboard'), findsOneWidget);
        expect(find.text('Welcome, ${role.displayLabel} User'), findsOneWidget);
        expect(find.byKey(const Key('login_email_field')), findsNothing);
      }
    });

    testWidgets('prevents unauthenticated navigation to protected routes', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureTokenStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            initialRoute: '/',
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/portal':
                case '/login':
                case '/':
                default:
                  return MaterialPageRoute(
                    settings: settings,
                    builder: (_) => const AuthGate(),
                  );
              }
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_email_field')), findsOneWidget);

      // Attempt to navigate directly to /portal while unauthenticated
      navKey.currentState!.pushNamed('/portal');
      await tester.pumpAndSettle();

      expect(find.text('Journalist Dashboard'), findsNothing);
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    });

    testWidgets('login unlocks app and logout redirects back to LoginScreen', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = InMemorySecureTokenStorage();
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated successfully.',
              'data': {
                'access_token': '20|jrn_gate_token',
                'token_type': 'Bearer',
                'user': _sessionForRole(PortalUserRole.reporter).user.toJson(),
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'message': 'Logged out successfully.'}),
          200,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureTokenStorageProvider.overrideWithValue(storage),
            authApiServiceProvider.overrideWithValue(
              AuthApiService(
                client: mockClient,
                baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
              ),
            ),
          ],
          child: const JournalistApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on LoginScreen
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'reporter@newsdesk.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'ChangeMe!2026',
      );

      final submitBtn = find.byKey(const Key('login_submit_button'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Now inside protected MainNavigationScreen
      expect(find.text('Journalist Dashboard'), findsOneWidget);
      expect(find.text('Welcome, Reporter User'), findsOneWidget);

      // Go to Profile and Logout
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profile_logout_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile_logout_tile')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_logout_button')));
      await tester.pumpAndSettle();

      // Redirected back to LoginScreen; Dashboard is inaccessible
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.text('Journalist Dashboard'), findsNothing);
      expect(await storage.readAccessToken(), isNull);
    });
  });
}
