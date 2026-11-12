import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/models/reporter.dart';
import 'package:journalist_app_1/repositories/auth_repository.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';

/// Real Laravel API implementation of [AuthRepository] backed by Sanctum and
/// platform-encrypted [SecureTokenStorage].
class ApiAuthRepository implements AuthRepository {
  final AuthApiService _apiService;
  final SecureTokenStorage _tokenStorage;
  final _authStateController = StreamController<Reporter?>.broadcast();

  AuthSession? _cachedSession;

  ApiAuthRepository({
    required AuthApiService apiService,
    required SecureTokenStorage tokenStorage,
  })  : _apiService = apiService,
        _tokenStorage = tokenStorage;

  @override
  Stream<Reporter?> get authStateChanges => _authStateController.stream;

  Future<AuthSession?> restoreSession() async {
    _cachedSession = await _tokenStorage.readSession();
    _authStateController.add(_cachedSession?.user.toReporter());
    return _cachedSession;
  }

  /// Restores any locally stored session and validates it against the backend
  /// via `GET /api/v1/auth/session-check`.
  ///
  /// Clears local session on confirmed `401` / `403` (`ACCOUNT_SUSPENDED` /
  /// `ACCOUNT_INACTIVE`), but preserves it on network or timeout errors.
  Future<AuthSession?> restoreAndValidateSession() async {
    final stored = await _tokenStorage.readSession();
    if (stored == null) {
      _cachedSession = null;
      _authStateController.add(null);
      return null;
    }

    try {
      final verifiedUser = await _apiService.checkSession(
        accessToken: stored.accessToken,
      );

      final mergedUser = AuthUser(
        id: verifiedUser.id != 0 ? verifiedUser.id : stored.user.id,
        uuid: verifiedUser.uuid.isNotEmpty
            ? verifiedUser.uuid
            : stored.user.uuid,
        userCode: verifiedUser.userCode.isNotEmpty
            ? verifiedUser.userCode
            : stored.user.userCode,
        name: verifiedUser.name.isNotEmpty
            ? verifiedUser.name
            : stored.user.name,
        email: verifiedUser.email.isNotEmpty
            ? verifiedUser.email
            : stored.user.email,
        role: verifiedUser.role,
        designation: stored.user.designation,
        assignedArea: stored.user.assignedArea,
        status: verifiedUser.status,
        isVerified: stored.user.isVerified,
        googleAccountEmail: stored.user.googleAccountEmail,
      );

      final refreshedSession = AuthSession(
        accessToken: stored.accessToken,
        tokenType: stored.tokenType,
        expiresAt: stored.expiresAt,
        abilities: stored.abilities,
        user: mergedUser,
      );

      await _tokenStorage.saveSession(refreshedSession);
      _cachedSession = refreshedSession;
      _authStateController.add(mergedUser.toReporter());
      return refreshedSession;
    } on AuthApiException catch (e) {
      if (e.type == AuthErrorType.unauthenticated ||
          e.type == AuthErrorType.accountSuspended ||
          e.type == AuthErrorType.accountInactive) {
        await _tokenStorage.clearSession();
        _cachedSession = null;
        _authStateController.add(null);
      }
      rethrow;
    }
  }

  @override
  Future<Reporter?> getCurrentReporter() async {
    _cachedSession ??= await _tokenStorage.readSession();
    return _cachedSession?.user.toReporter();
  }

  /// Authenticates against `POST /api/v1/auth/login` and securely stores the
  /// returned Sanctum token and session metadata.
  Future<AuthSession> loginWithCredentials({
    required String email,
    required String password,
  }) async {
    final deviceId = await _tokenStorage.getOrCreateDeviceId();
    final deviceName = kIsWeb
        ? 'Flutter (web)'
        : 'Flutter (${Platform.operatingSystem})';

    final session = await _apiService.login(
      email: email,
      password: password,
      deviceId: deviceId,
      deviceName: deviceName,
    );

    await _tokenStorage.saveSession(session);
    _cachedSession = session;
    _authStateController.add(session.user.toReporter());
    return session;
  }

  @override
  Future<bool> login({
    required String emailOrUsername,
    required String password,
  }) async {
    await loginWithCredentials(email: emailOrUsername, password: password);
    return true;
  }

  /// Calls `POST /api/v1/auth/logout` and clears local session only when the
  /// server confirms revocation or reports the token is already invalid (`401`/`403`).
  Future<LogoutApiOutcome> logoutCurrentSession() async {
    final token = _cachedSession?.accessToken ?? await _tokenStorage.readAccessToken();

    if (token == null || token.trim().isEmpty) {
      await _tokenStorage.clearSession();
      _cachedSession = null;
      _authStateController.add(null);
      return const LogoutApiOutcome(
        revokedOnServer: true,
        alreadyExpired: true,
        message: 'Signed out locally.',
      );
    }

    final outcome = await _apiService.logout(accessToken: token);

    await _tokenStorage.clearSession();
    _cachedSession = null;
    _authStateController.add(null);
    return outcome;
  }

  @override
  Future<void> logout() async {
    await logoutCurrentSession();
  }
}

