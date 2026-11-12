import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/core/constants/app_config.dart';
import 'package:journalist_app_1/main.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/screens/login_screen.dart';
import 'package:journalist_app_1/screens/main_navigation_screen.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';

class InMemorySecureTokenStorage implements SecureTokenStorage {
  AuthSession? storedSession;
  String? storedToken;
  String deviceId = 'test_device_01';
  final Map<String, String> linkedDriveEmails = {};

  @override
  Future<void> clearSession() async {
    storedSession = null;
    storedToken = null;
  }

  @override
  Future<String> getOrCreateDeviceId() async => deviceId;

  @override
  Future<String?> readAccessToken() async => storedToken;

  @override
  Future<AuthSession?> readSession() async {
    if (storedSession != null && storedSession!.isExpired) {
      await clearSession();
      return null;
    }
    return storedSession;
  }

  @override
  Future<void> saveSession(AuthSession session) async {
    storedSession = session;
    storedToken = session.accessToken;
  }

  @override
  Future<void> clearLinkedGoogleDriveEmail({required String userKey}) async {
    linkedDriveEmails.remove(userKey);
  }

  @override
  Future<String?> readLinkedGoogleDriveEmail({required String userKey}) async {
    return linkedDriveEmails[userKey];
  }

  @override
  Future<void> saveLinkedGoogleDriveEmail({
    required String userKey,
    required String googleEmail,
  }) async {
    linkedDriveEmails[userKey] = googleEmail;
  }
}

Map<String, dynamic> _buildLoginSuccessJson({
  required String role,
  String name = 'Test User',
  String email = 'user@newsdesk.local',
  String userCode = 'REP-2026-084',
  String token = '1|jrn_mock_sanctum_token',
}) {
  return {
    'success': true,
    'message': 'Authenticated successfully.',
    'data': {
      'access_token': token,
      'token_type': 'Bearer',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
      'abilities': ['news:submit', 'news:read'],
      'user': {
        'id': 4,
        'uuid': 'uuid-$role-001',
        'user_code': userCode,
        'name': name,
        'email': email,
        'role': role,
        'designation': 'Staff Correspondent',
        'assigned_area': 'Dhaka Metro',
        'status': 'active',
        'is_verified': true,
        'google_account_email': null,
      },
    },
  };
}

void main() {
  group('AppConfig & AuthApiService Tests', () {
    test('AppConfig apiBaseUrl points to local dev host without secrets', () {
      final url = AppConfig.apiBaseUrl;
      expect(url, endsWith('/api/v1'));
      expect(url.contains('secret'), isFalse);
      expect(url.contains('password'), isFalse);
    });

    test('AuthApiService parses all four supported roles cleanly', () async {
      for (final roleEntry in {
        'reporter': PortalUserRole.reporter,
        'editor': PortalUserRole.editor,
        'senior_editor': PortalUserRole.seniorEditor,
        'admin': PortalUserRole.admin,
      }.entries) {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('POST'));
          expect(request.url.toString(), equals('http://10.0.2.2:8000/api/v1/auth/login'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['email'], equals('staff@newsdesk.local'));
          expect(body['password'], equals('ChangeMe!2026'));

          return http.Response(
            jsonEncode(_buildLoginSuccessJson(
              role: roleEntry.key,
              email: 'staff@newsdesk.local',
            )),
            200,
          );
        });

        final service = AuthApiService(
          client: mockClient,
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        );

        final session = await service.login(
          email: 'staff@newsdesk.local',
          password: 'ChangeMe!2026',
          deviceId: 'emu_01',
          deviceName: 'Android Emulator',
        );

        expect(session.accessToken, equals('1|jrn_mock_sanctum_token'));
        expect(session.user.role, equals(roleEntry.value));
      }
    });

    test('AuthApiService maps 401, 403 suspended, 429, and network errors', () async {
      Future<AuthApiException> expectAuthError(http.Client client) async {
        final service = AuthApiService(
          client: client,
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        );
        try {
          await service.login(email: 'a@b.com', password: 'Password!1');
          fail('Expected AuthApiException');
        } on AuthApiException catch (e) {
          return e;
        }
      }

      final invalidCreds = await expectAuthError(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'INVALID_CREDENTIALS',
                'message': 'The provided email or password is incorrect.',
              },
            }),
            401,
          ),
        ),
      );
      expect(invalidCreds.type, equals(AuthErrorType.invalidCredentials));
      expect(invalidCreds.statusCode, equals(401));

      final suspended = await expectAuthError(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'ACCOUNT_SUSPENDED',
                'message': 'Your account has been suspended.',
              },
            }),
            403,
          ),
        ),
      );
      expect(suspended.type, equals(AuthErrorType.accountSuspended));
      expect(suspended.statusCode, equals(403));

      final rateLimited = await expectAuthError(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'RATE_LIMIT_EXCEEDED',
                'message': 'Too many requests.',
              },
            }),
            429,
          ),
        ),
      );
      expect(rateLimited.type, equals(AuthErrorType.rateLimited));

      final networkErr = await expectAuthError(
        MockClient((_) async => throw const SocketException('Connection refused')),
      );
      expect(networkErr.type, equals(AuthErrorType.networkError));

      final timeoutErr = await expectAuthError(
        MockClient((_) async => throw TimeoutException('Timed out')),
      );
      expect(timeoutErr.type, equals(AuthErrorType.timeout));
    });
  });

  group('Riverpod AuthState & Secure Storage Persistence Tests', () {
    test('AuthNotifier persists token in SecureTokenStorage and restores session', () async {
      final storage = InMemorySecureTokenStorage();
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode(
            _buildLoginSuccessJson(
              role: 'senior_editor',
              name: 'Chief Desk Editor',
              email: 'senior.editor@newsdesk.local',
              userCode: 'SED-2026-002',
              token: '2|jrn_senior_editor_token',
            ),
          ),
          200,
        ),
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

      final success = await container.read(authStateProvider.notifier).login(
            email: 'senior.editor@newsdesk.local',
            password: 'ChangeMe!2026',
          );

      expect(success, isTrue);
      expect(container.read(authStateProvider).isAuthenticated, isTrue);
      expect(
        container.read(authStateProvider).user?.role,
        equals(PortalUserRole.seniorEditor),
      );
      expect(await storage.readAccessToken(), equals('2|jrn_senior_editor_token'));

      // Simulate fresh app restart using same SecureTokenStorage
      final restoredMockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _buildLoginSuccessJson(
                role: 'senior_editor',
                name: 'Chief Desk Editor',
                email: 'senior.editor@newsdesk.local',
                userCode: 'SED-2026-002',
                token: '2|jrn_senior_editor_token',
              )['data']['user'],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': false, 'message': 'Not found'}),
          404,
        );
      });

      final restoredContainer = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: restoredMockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
        ],
      );
      addTearDown(restoredContainer.dispose);

      await restoredContainer.read(authStateProvider.notifier).restoreSession();
      final restored = restoredContainer.read(authStateProvider);
      expect(restored.isAuthenticated, isTrue);
      expect(restored.user?.email, equals('senior.editor@newsdesk.local'));
      expect(restored.session?.accessToken, equals('2|jrn_senior_editor_token'));
    });
  });

  group('LoginScreen Widget Tests', () {
    testWidgets('validates empty/invalid input, shows loading, and handles errors', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      final completer = Completer<http.Response>();

      final mockClient = MockClient((_) => completer.future);

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
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Submit empty form -> validation messages
      final submitBtn = find.byKey(const Key('login_submit_button'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pump();
      expect(find.text('Please enter your official email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);

      // Enter valid email + valid password
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'suspended@newsdesk.local',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'ChangeMe!2026',
      );

      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pump();

      // Loading indicator shown while request is in flight
      expect(find.text('Signing In...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete with 403 ACCOUNT_SUSPENDED
      completer.complete(
        http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'ACCOUNT_SUSPENDED',
              'message':
                  'Your account has been suspended. Please contact a newsroom administrator.',
            },
          }),
          403,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_error_banner')), findsOneWidget);
      expect(
        find.textContaining('Your account has been suspended.'),
        findsOneWidget,
      );
    });

    testWidgets('successful login navigates to dashboard and shows user role', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode(
            _buildLoginSuccessJson(
              role: 'editor',
              name: 'Farhana Karim',
              email: 'editor@newsdesk.local',
              userCode: 'EDT-2026-003',
              token: '3|jrn_editor_token',
            ),
          ),
          200,
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
          child: MaterialApp(
            initialRoute: '/login',
            routes: {
              '/': (context) => const MainNavigationScreen(),
              '/login': (context) => const LoginScreen(),
            },
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'editor@newsdesk.local',
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

      expect(find.text('Journalist Dashboard'), findsOneWidget);
      expect(find.text('Welcome, Farhana Karim'), findsOneWidget);
      expect(find.text('Editor • EDT-2026-003'), findsOneWidget);

      // Navigate to Profile tab and verify user profile + Google Drive Storage remain independent
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Farhana Karim'), findsOneWidget);
      expect(find.text('Google Drive Storage'), findsOneWidget);
    });

    testWidgets('Dashboard Pending and Published cards open filtered news lists', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();
      final loginJson = _buildLoginSuccessJson(role: 'reporter');
      await storage.saveSession(
        AuthSession.fromLoginDataJson(
          loginJson['data'] as Map<String, dynamic>,
        ),
      );
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': (loginJson['data'] as Map<String, dynamic>)['user'],
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

      // Tap Pending card -> opens MyNewsScreen filtered to Pending
      await tester.tap(find.text('Pending'));
      await tester.pumpAndSettle();
      expect(find.text('REP-103'), findsOneWidget);
      expect(find.text('REP-101'), findsNothing);

      // Go back and tap Published card -> opens MyNewsScreen filtered to Published
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Published').first);
      await tester.pumpAndSettle();
      expect(find.text('REP-101'), findsOneWidget);
      expect(find.text('REP-103'), findsNothing);
    });

    testWidgets('unauthenticated app starts on LoginScreen via AuthGate', (
      WidgetTester tester,
    ) async {
      final storage = InMemorySecureTokenStorage();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureTokenStorageProvider.overrideWithValue(storage),
          ],
          child: const JournalistApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.text('Journalist Dashboard'), findsNothing);
    });
  });
}

