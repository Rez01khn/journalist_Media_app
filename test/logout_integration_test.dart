import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/screens/profile_screen.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';

import 'login_integration_test.dart' show InMemorySecureTokenStorage;

AuthSession _sampleSession({String token = '1|jrn_active_sanctum_token'}) {
  return AuthSession(
    accessToken: token,
    tokenType: 'Bearer',
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    abilities: const ['news:submit', 'news:read'],
    user: const AuthUser(
      id: 4,
      uuid: 'uuid-rep-004',
      userCode: 'REP-2026-084',
      name: 'Rezwan Ahmed',
      email: 'reporter@newsdesk.local',
      role: PortalUserRole.reporter,
      designation: 'Staff Reporter',
      assignedArea: 'Dhaka Metro',
    ),
  );
}

void main() {
  group('TASK 06.7 — AuthApiService & AuthNotifier Logout Tests', () {
    test('successful logout revokes token via API, clears storage, and updates state', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '10|jrn_logout_token'));

      var logoutCalls = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        logoutCalls++;
        expect(request.method, equals('POST'));
        expect(request.url.toString(), equals('http://10.0.2.2:8000/api/v1/auth/logout'));
        expect(request.headers['Authorization'], equals('Bearer 10|jrn_logout_token'));

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Logged out successfully.',
            'data': {'logged_out': true},
          }),
          200,
        );
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

      await container.read(authStateProvider.notifier).restoreSession();
      expect(container.read(authStateProvider).isAuthenticated, isTrue);

      final result = await container.read(authStateProvider.notifier).logout();

      expect(logoutCalls, equals(1));
      expect(result.success, isTrue);
      expect(result.alreadyExpired, isFalse);
      expect(container.read(authStateProvider).status, equals(AuthStatus.unauthenticated));
      expect(container.read(authStateProvider).isAuthenticated, isFalse);
      expect(container.read(authStateProvider).user, isNull);
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readSession(), isNull);
    });

    test('401 expired or revoked token safely clears local session', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '11|jrn_expired_token'));

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'UNAUTHENTICATED', 'message': 'Unauthenticated.'},
          }),
          401,
        );
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

      await container.read(authStateProvider.notifier).restoreSession();
      final result = await container.read(authStateProvider.notifier).logout();

      expect(result.success, isTrue);
      expect(result.alreadyExpired, isTrue);
      expect(container.read(authStateProvider).status, equals(AuthStatus.unauthenticated));
      expect(await storage.readAccessToken(), isNull);
    });

    test('network failure preserves local session and does not falsely claim revocation', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '12|jrn_offline_token'));

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        throw const SocketException('Network unreachable');
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

      await container.read(authStateProvider.notifier).restoreSession();
      final result = await container.read(authStateProvider.notifier).logout();

      expect(result.success, isFalse);
      expect(result.errorType, equals(AuthErrorType.networkError));
      expect(result.message.toLowerCase(), isNot(contains('logged out successfully')));
      expect(container.read(authStateProvider).isAuthenticated, isTrue);
      expect(await storage.readAccessToken(), equals('12|jrn_offline_token'));
    });

    test('prevents duplicate concurrent logout requests', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '13|jrn_dup_token'));

      final completer = Completer<http.Response>();
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        requestCount++;
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

      await container.read(authStateProvider.notifier).restoreSession();

      final firstFuture = container.read(authStateProvider.notifier).logout();
      final secondResult = await container.read(authStateProvider.notifier).logout();

      expect(secondResult.success, isFalse);
      expect(secondResult.ignoredDuplicate, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(requestCount, equals(1));

      completer.complete(
        http.Response(
          jsonEncode({'success': true, 'message': 'Logged out successfully.'}),
          200,
        ),
      );

      final firstResult = await firstFuture;
      expect(firstResult.success, isTrue);
      expect(requestCount, equals(1));
      expect(container.read(authStateProvider).status, equals(AuthStatus.unauthenticated));
    });

    test('backend logout never disconnects Google Drive OAuth state', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession());

      final mockDriveRepo = MockGoogleDriveRepository();
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'message': 'Logged out successfully.'}),
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
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
      await container
          .read(googleDriveStateProvider.notifier)
          .connectAccount(preferredEmail: 'reporter.drive@gmail.com');

      expect(container.read(googleDriveStateProvider).isConnected, isTrue);

      final result = await container.read(authStateProvider.notifier).logout();
      expect(result.success, isTrue);
      expect(container.read(authStateProvider).isAuthenticated, isFalse);
      expect(container.read(googleDriveStateProvider).isConnected, isTrue);
      expect(
        container.read(googleDriveStateProvider).accountEmail,
        equals('reporter.drive@gmail.com'),
      );
    });

    test('persisted Google Drive connection restores automatically after logout and re-login', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '15|jrn_first_login'));

      final mockDriveRepo = MockGoogleDriveRepository();
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated successfully.',
              'data': {
                'access_token': '16|jrn_second_login',
                'token_type': 'Bearer',
                'user': _sampleSession().user.toJson(),
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

      final container1 = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(container1.dispose);

      await container1.read(authStateProvider.notifier).restoreSession();
      await container1
          .read(googleDriveStateProvider.notifier)
          .connectAccount(preferredEmail: 'reporter.drive@gmail.com');
      expect(container1.read(googleDriveStateProvider).isConnected, isTrue);

      // Logout and simulate fresh container / restart
      await container1.read(authStateProvider.notifier).logout();
      await mockDriveRepo.disconnectDrive();

      final container2 = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(container2.dispose);

      final loggedIn = await container2.read(authStateProvider.notifier).login(
            email: 'reporter@newsdesk.local',
            password: 'ChangeMe!2026',
          );
      expect(loggedIn, isTrue);

      await container2.read(googleDriveStateProvider.notifier).checkConnectionStatus();
      expect(container2.read(googleDriveStateProvider).isConnected, isTrue);
      expect(
        container2.read(googleDriveStateProvider).accountEmail,
        equals('reporter.drive@gmail.com'),
      );
    });
  });

  group('TASK 06.7 — ProfileScreen Logout UI Tests', () {
    testWidgets('authenticated ProfileScreen confirms logout and switches to signed-out UI', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = InMemorySecureTokenStorage();
      await storage.saveSession(_sampleSession(token: '14|jrn_ui_token'));

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'message': 'Logged out successfully.'}),
          200,
        );
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

      await container.read(authStateProvider.notifier).restoreSession();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rezwan Ahmed'), findsOneWidget);
      expect(find.byKey(const Key('profile_logout_tile')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('profile_logout_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile_logout_tile')));
      await tester.pumpAndSettle();

      expect(find.text('Logout of Newsroom Account?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_logout_button')));
      await tester.pumpAndSettle();

      expect(find.text('Sign In or Sign Up'), findsOneWidget);
      expect(find.byKey(const Key('profile_logout_tile')), findsNothing);
      expect(await storage.readAccessToken(), isNull);
    });
  });
}

