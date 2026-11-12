import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/main.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/providers/auth_provider.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';

import 'login_integration_test.dart' show InMemorySecureTokenStorage;

AuthSession _sampleSession({
  String token = '20|jrn_valid_session_token',
  PortalUserRole role = PortalUserRole.reporter,
}) {
  return AuthSession(
    accessToken: token,
    tokenType: 'Bearer',
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    abilities: const ['*'],
    user: AuthUser(
      id: 4,
      uuid: 'uuid-reporter-4',
      userCode: 'REP-2026-004',
      name: 'Rezwan Ahmed',
      email: 'reporter@newsdesk.local',
      role: role,
      designation: 'Staff Reporter',
      assignedArea: 'Dhaka Metro',
    ),
  );
}

Map<String, dynamic> _sessionCheckSuccessJson({
  String name = 'Rezwan Ahmed',
  String role = 'reporter',
  String status = 'active',
}) {
  return {
    'success': true,
    'message': 'Authenticated session is active.',
    'data': {
      'id': 4,
      'uuid': 'uuid-reporter-4',
      'user_code': 'REP-2026-004',
      'name': name,
      'email': 'reporter@newsdesk.local',
      'role': role,
      'status': status,
      'designation': 'Staff Reporter',
      'assigned_area': 'Dhaka Metro',
    },
  };
}

void main() {
  group('TASK 06.9 — Backend Session Validation Tests', () {
    testWidgets('valid session-check (200) confirms session and grants access to MainNavigationScreen', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession());

      String? authHeader;
      String? requestedPath;
      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        authHeader = request.headers['Authorization'];
        return http.Response(
          jsonEncode(_sessionCheckSuccessJson(name: 'Rezwan Updated')),
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

      expect(requestedPath, endsWith('/auth/session-check'));
      expect(authHeader, equals('Bearer 20|jrn_valid_session_token'));
      expect(find.text('Journalist Dashboard'), findsOneWidget);
      expect(find.text('Welcome, Rezwan Updated'), findsOneWidget);
      expect(find.byKey(const Key('auth_gate_retry_screen')), findsNothing);
      expect(find.byKey(const Key('login_email_field')), findsNothing);

      final updatedSession = await storage.readSession();
      expect(updatedSession, isNotNull);
      expect(updatedSession!.user.name, equals('Rezwan Updated'));
    });

    testWidgets('401 session-check clears local session and redirects to LoginScreen', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '21|jrn_revoked_token'));

      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Unauthenticated.',
            },
          }),
          401,
        ),
      );

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

      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readSession(), isNull);
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.text('Journalist Dashboard'), findsNothing);
      expect(find.byKey(const Key('auth_gate_retry_screen')), findsNothing);
    });

    testWidgets('403 ACCOUNT_SUSPENDED clears local session and redirects to LoginScreen', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '22|jrn_suspended_token'));

      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'ACCOUNT_SUSPENDED',
              'message': 'Your account has been suspended by an administrator.',
            },
          }),
          403,
        ),
      );

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

      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readSession(), isNull);
      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.text('Journalist Dashboard'), findsNothing);
    });

    testWidgets('network failure allows offline entry with saved session and revalidates when back online', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '23|jrn_offline_token'));

      var shouldFailNetwork = true;
      var return401OnOnline = false;
      final mockClient = MockClient((_) async {
        if (shouldFailNetwork) {
          throw const SocketException('Connection refused');
        }
        if (return401OnOnline) {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {'code': 'UNAUTHENTICATED', 'message': 'Unauthenticated.'},
            }),
            401,
          );
        }
        return http.Response(jsonEncode(_sessionCheckSuccessJson()), 200);
      });

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const JournalistApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Token must NOT be deleted on network failure, and user enters app offline.
      expect(await storage.readAccessToken(), equals('23|jrn_offline_token'));
      expect(find.text('Journalist Dashboard'), findsOneWidget);
      expect(container.read(authStateProvider).isOfflineSession, isTrue);

      // When network recovers with valid session, offline flag clears.
      shouldFailNetwork = false;
      await container.read(authStateProvider.notifier).revalidateOfflineSessionIfNeeded();
      await tester.pumpAndSettle();
      expect(container.read(authStateProvider).isOfflineSession, isFalse);
      expect(container.read(authStateProvider).isAuthenticated, isTrue);

      // Simulate another offline boot then revoked token on reconnect -> logs out.
      final container2 = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(container2.dispose);
      shouldFailNetwork = true;
      await container2.read(authStateProvider.notifier).restoreSession();
      expect(container2.read(authStateProvider).isAuthenticated, isTrue);
      expect(container2.read(authStateProvider).isOfflineSession, isTrue);

      shouldFailNetwork = false;
      return401OnOnline = true;
      await container2.read(authStateProvider.notifier).revalidateOfflineSessionIfNeeded();
      expect(container2.read(authStateProvider).isAuthenticated, isFalse);
      expect(await storage.readAccessToken(), isNull);
    });

    test('timeout preserves local session and grants offline access until online revalidation', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '24|jrn_timeout_token'));

      final mockClient = MockClient(
        (_) async => throw TimeoutException('Request timed out'),
      );

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authStateProvider.notifier).restoreSession();

      final state = container.read(authStateProvider);
      expect(state.status, equals(AuthStatus.authenticated));
      expect(state.isAuthenticated, isTrue);
      expect(state.isOfflineSession, isTrue);
      expect(await storage.readAccessToken(), equals('24|jrn_timeout_token'));
    });

    test('prevents duplicate concurrent session-check requests', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '25|jrn_dup_check'));

      final completer = Completer<http.Response>();
      var checkCalls = 0;
      final mockClient = MockClient((request) {
        if (request.url.path.endsWith('/auth/session-check')) {
          checkCalls++;
        }
        return completer.future;
      });

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final firstCall = container.read(authStateProvider.notifier).restoreSession();
      final secondCall = container.read(authStateProvider.notifier).restoreSession();
      final thirdCall = container.read(authStateProvider.notifier).retrySessionValidation();

      await Future<void>.delayed(Duration.zero);
      expect(checkCalls, equals(1));

      completer.complete(
        http.Response(jsonEncode(_sessionCheckSuccessJson()), 200),
      );

      await Future.wait([firstCall, secondCall, thirdCall]);
      expect(checkCalls, equals(1));
      expect(container.read(authStateProvider).isAuthenticated, isTrue);
    });
  });
}

