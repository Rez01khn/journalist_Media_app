import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/repositories/api_auth_repository.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';

enum AuthStatus {
  initial,
  validatingSession,
  loading,
  authenticated,
  unauthenticated,
  sessionValidationError,
  error,
}

class LogoutResult {
  final bool success;
  final bool alreadyExpired;
  final bool ignoredDuplicate;
  final String message;
  final AuthErrorType? errorType;

  const LogoutResult({
    required this.success,
    this.alreadyExpired = false,
    this.ignoredDuplicate = false,
    required this.message,
    this.errorType,
  });
}

class AuthState {
  final AuthStatus status;
  final AuthSession? session;
  final String? errorMessage;
  final AuthErrorType? errorType;
  final bool isLoggingOut;
  final bool isOfflineSession;

  const AuthState({
    this.status = AuthStatus.initial,
    this.session,
    this.errorMessage,
    this.errorType,
    this.isLoggingOut = false,
    this.isOfflineSession = false,
  });

  bool get isLoading => status == AuthStatus.loading;
  bool get isValidatingSession =>
      status == AuthStatus.initial || status == AuthStatus.validatingSession;
  bool get isAuthenticated =>
      status == AuthStatus.authenticated && session != null;
  AuthUser? get user => session?.user;

  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    bool clearSession = false,
    String? errorMessage,
    AuthErrorType? errorType,
    bool clearError = false,
    bool? isLoggingOut,
    bool? isOfflineSession,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
      isLoggingOut: isLoggingOut ?? this.isLoggingOut,
      isOfflineSession: isOfflineSession ?? this.isOfflineSession,
    );
  }
}

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return const FlutterSecureTokenStorage();
});

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  return AuthApiService();
});

final apiAuthRepositoryProvider = Provider<ApiAuthRepository>((ref) {
  return ApiAuthRepository(
    apiService: ref.watch(authApiServiceProvider),
    tokenStorage: ref.watch(secureTokenStorageProvider),
  );
});

class AuthNotifier extends Notifier<AuthState> {
  static const EventChannel _connectivityChannel = EventChannel(
    'com.example.journalist_app_1/connectivity',
  );

  bool _hasRestored = false;
  bool _validationInFlight = false;
  bool _logoutInFlight = false;
  StreamSubscription<dynamic>? _connectivitySub;

  @override
  AuthState build() {
    _startConnectivityListener();
    ref.onDispose(() {
      _connectivitySub?.cancel();
      _connectivitySub = null;
    });
    return const AuthState(status: AuthStatus.initial);
  }

  void _startConnectivityListener() {
    if (!Platform.isAndroid ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      _connectivitySub?.cancel();
      _connectivitySub = _connectivityChannel.receiveBroadcastStream().listen((
        dynamic event,
      ) {
        if (event == true) {
          Future.microtask(revalidateOfflineSessionIfNeeded);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Restores and server-validates any saved Sanctum session once on startup.
  /// If offline with a saved local session, grants offline access and
  /// revalidates automatically once connectivity returns.
  Future<void> restoreSession() async {
    if (_hasRestored || _validationInFlight || state.isLoading) return;
    _hasRestored = true;
    await _validateStoredSession();
  }

  /// Retries backend session validation after a network/timeout failure.
  Future<void> retrySessionValidation() async {
    if (_validationInFlight || state.isLoading) return;
    await _validateStoredSession();
  }

  /// Revalidates an offline-restored session once the device comes back online.
  Future<void> revalidateOfflineSessionIfNeeded() async {
    if (!state.isAuthenticated ||
        !state.isOfflineSession ||
        _validationInFlight ||
        state.isLoading ||
        _logoutInFlight) {
      return;
    }
    _validationInFlight = true;
    try {
      final session = await ref
          .read(apiAuthRepositoryProvider)
          .restoreAndValidateSession();
      if (session != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          session: session,
          isOfflineSession: false,
        );
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } on AuthApiException catch (e) {
      if (e.type == AuthErrorType.unauthenticated ||
          e.type == AuthErrorType.accountSuspended ||
          e.type == AuthErrorType.accountInactive) {
        state = AuthState(
          status: AuthStatus.error,
          errorMessage: e.message,
          errorType: e.type,
        );
      }
    } catch (_) {
      // Still offline; keep offline authenticated session intact.
    } finally {
      _validationInFlight = false;
    }
  }

  Future<void> _validateStoredSession() async {
    if (_validationInFlight) return;
    _validationInFlight = true;

    state = state.copyWith(
      status: AuthStatus.validatingSession,
      clearError: true,
    );

    AuthSession? localSession;
    try {
      localSession = await ref.read(secureTokenStorageProvider).readSession();
      if (localSession == null) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }

      final session = await ref
          .read(apiAuthRepositoryProvider)
          .restoreAndValidateSession();
      if (session != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          session: session,
          isOfflineSession: false,
        );
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } on AuthApiException catch (e) {
      if (e.type == AuthErrorType.unauthenticated ||
          e.type == AuthErrorType.accountSuspended ||
          e.type == AuthErrorType.accountInactive) {
        // Local session already cleared by repository; redirect to LoginScreen.
        state = AuthState(
          status: AuthStatus.error,
          errorMessage: e.message,
          errorType: e.type,
        );
      } else if (localSession != null) {
        // Offline/timeout/server 5xx with a saved local session: allow full
        // offline access and revalidate automatically when back online.
        state = AuthState(
          status: AuthStatus.authenticated,
          session: localSession,
          isOfflineSession: true,
        );
      } else {
        state = AuthState(
          status: AuthStatus.sessionValidationError,
          errorMessage: e.message,
          errorType: e.type,
        );
      }
    } catch (_) {
      if (localSession != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          session: localSession,
          isOfflineSession: true,
        );
      } else {
        state = const AuthState(
          status: AuthStatus.sessionValidationError,
          errorMessage:
              'Unable to verify your session right now. Please check your connection and retry.',
          errorType: AuthErrorType.networkError,
        );
      }
    } finally {
      _validationInFlight = false;
    }
  }

  /// Switches from a retryable session-validation error screen to LoginScreen
  /// without falsely claiming server-side token revocation.
  void proceedToLogin() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Authenticates against Laravel `POST /api/v1/auth/login`.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      clearError: true,
    );

    try {
      final session = await ref
          .read(apiAuthRepositoryProvider)
          .loginWithCredentials(email: email, password: password);

      state = AuthState(
        status: AuthStatus.authenticated,
        session: session,
      );
      return true;
    } on AuthApiException catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        session: state.session,
        errorMessage: e.message,
        errorType: e.type,
      );
      return false;
    } catch (_) {
      state = AuthState(
        status: AuthStatus.error,
        session: state.session,
        errorMessage: 'An unexpected error occurred while signing in.',
        errorType: AuthErrorType.serverError,
      );
      return false;
    }
  }

  /// Revokes the current device's Sanctum token via `POST /api/v1/auth/logout`.
  ///
  /// Does not touch Google Drive OAuth or SQLite drafts.
  /// Preserves local session on network failure so we never falsely claim revocation.
  Future<LogoutResult> logout() async {
    if (_logoutInFlight || state.isLoggingOut || state.isLoading) {
      return const LogoutResult(
        success: false,
        ignoredDuplicate: true,
        message: 'Logout is already in progress.',
      );
    }

    _logoutInFlight = true;
    state = state.copyWith(
      isLoggingOut: true,
      clearError: true,
    );

    try {
      final outcome =
          await ref.read(apiAuthRepositoryProvider).logoutCurrentSession();

      state = const AuthState(
        status: AuthStatus.unauthenticated,
        isLoggingOut: false,
      );

      return LogoutResult(
        success: true,
        alreadyExpired: outcome.alreadyExpired,
        message: outcome.message,
      );
    } on AuthApiException catch (e) {
      state = state.copyWith(
        status: state.session != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        isLoggingOut: false,
        errorMessage: e.message,
        errorType: e.type,
      );
      return LogoutResult(
        success: false,
        message: e.message,
        errorType: e.type,
      );
    } catch (_) {
      const msg = 'Unexpected error while logging out. Please try again.';
      state = state.copyWith(
        status: state.session != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        isLoggingOut: false,
        errorMessage: msg,
        errorType: AuthErrorType.serverError,
      );
      return const LogoutResult(
        success: false,
        message: msg,
        errorType: AuthErrorType.serverError,
      );
    } finally {
      _logoutInFlight = false;
    }
  }

  void clearError() {
    if (state.errorMessage != null || state.status == AuthStatus.error) {
      state = state.copyWith(
        status: state.session != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        clearError: true,
      );
    }
  }
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
