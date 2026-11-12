import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:journalist_app_1/core/constants/app_config.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';

/// Categorized errors returned during Laravel API authentication.
enum AuthErrorType {
  invalidCredentials,
  unauthenticated,
  accountSuspended,
  accountInactive,
  accountLocked,
  rateLimited,
  validationError,
  networkError,
  timeout,
  serverError,
}

/// Typed exception for Laravel `/api/v1/auth/login` failures.
class AuthApiException implements Exception {
  final AuthErrorType type;
  final String code;
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  const AuthApiException({
    required this.type,
    required this.code,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
  });

  @override
  String toString() => 'AuthApiException($code, status=$statusCode): $message';
}

/// Outcome of calling `POST /api/v1/auth/logout`.
class LogoutApiOutcome {
  final bool revokedOnServer;
  final bool alreadyExpired;
  final String message;

  const LogoutApiOutcome({
    required this.revokedOnServer,
    required this.alreadyExpired,
    required this.message,
  });
}

/// HTTP client integrating `POST /api/v1/auth/login` and `/api/v1/auth/logout`.
///
/// Completely separate from Google Sign-In / Google Drive OAuth.
class AuthApiService {
  final http.Client _client;
  final String Function() _baseUrlResolver;
  final Duration _timeout;

  AuthApiService({
    http.Client? client,
    String Function()? baseUrlResolver,
    Duration timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _baseUrlResolver = baseUrlResolver ?? (() => AppConfig.apiBaseUrl),
        _timeout = timeout;

  Future<AuthSession> login({
    required String email,
    required String password,
    String? deviceId,
    String? deviceName,
  }) async {
    final baseUrl = _baseUrlResolver().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/auth/login');

    final payload = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'device_id': deviceId.trim(),
      if (deviceName != null && deviceName.trim().isNotEmpty)
        'device_name': deviceName.trim(),
    };

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
              'X-Client-Version': 'flutter-mobile/1.0.0',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AuthApiException(
        type: AuthErrorType.timeout,
        code: 'REQUEST_TIMEOUT',
        message:
            'The server took too long to respond. Please check your connection and try again.',
      );
    } on SocketException {
      throw const AuthApiException(
        type: AuthErrorType.networkError,
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the newsroom server. Please verify your internet connection.',
      );
    } on http.ClientException catch (e) {
      throw AuthApiException(
        type: AuthErrorType.networkError,
        code: 'NETWORK_ERROR',
        message:
            'Network connection failed (${e.message}). Please verify the API server is reachable.',
      );
    }

    Map<String, dynamic> bodyJson;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected non-object JSON response.');
      }
      bodyJson = decoded;
    } catch (_) {
      throw AuthApiException(
        type: AuthErrorType.serverError,
        code: 'INVALID_RESPONSE',
        statusCode: response.statusCode,
        message: 'Unexpected response from server (HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        bodyJson['success'] == true) {
      final data = bodyJson['data'];
      if (data is! Map<String, dynamic>) {
        throw AuthApiException(
          type: AuthErrorType.serverError,
          code: 'INVALID_RESPONSE',
          statusCode: response.statusCode,
          message: 'Login response did not include session data.',
        );
      }
      try {
        return AuthSession.fromLoginDataJson(data);
      } on FormatException catch (e) {
        throw AuthApiException(
          type: AuthErrorType.serverError,
          code: 'INVALID_RESPONSE',
          statusCode: response.statusCode,
          message: e.message,
        );
      }
    }

    throw _mapErrorResponse(response.statusCode, bodyJson);
  }

  AuthApiException _mapErrorResponse(
    int statusCode,
    Map<String, dynamic> bodyJson,
  ) {
    final errorObj = bodyJson['error'];
    final code = errorObj is Map<String, dynamic>
        ? (errorObj['code'] as String? ?? 'AUTH_ERROR')
        : 'AUTH_ERROR';
    final serverMessage = errorObj is Map<String, dynamic>
        ? (errorObj['message'] as String?)
        : (bodyJson['message'] as String?);

    final fieldErrors = <String, List<String>>{};
    if (errorObj is Map<String, dynamic> &&
        errorObj['details'] is Map<String, dynamic>) {
      final details = errorObj['details'] as Map<String, dynamic>;
      details.forEach((key, value) {
        if (value is List) {
          fieldErrors[key] = value.whereType<String>().toList(growable: false);
        }
      });
    }

    if (code == 'INVALID_CREDENTIALS' || statusCode == 401) {
      return AuthApiException(
        type: AuthErrorType.invalidCredentials,
        code: code,
        statusCode: statusCode,
        message:
            serverMessage ?? 'Invalid email or password. Please try again.',
      );
    }

    if (code == 'ACCOUNT_SUSPENDED') {
      return AuthApiException(
        type: AuthErrorType.accountSuspended,
        code: code,
        statusCode: statusCode,
        message: serverMessage ??
            'Your account has been suspended. Please contact a newsroom administrator.',
      );
    }

    if (code == 'ACCOUNT_INACTIVE' || statusCode == 403) {
      return AuthApiException(
        type: AuthErrorType.accountInactive,
        code: code,
        statusCode: statusCode,
        message:
            serverMessage ?? 'Your account is not active or verified yet.',
      );
    }

    if (code == 'ACCOUNT_LOCKED' || statusCode == 423) {
      return AuthApiException(
        type: AuthErrorType.accountLocked,
        code: code,
        statusCode: statusCode,
        message: serverMessage ??
            'Too many failed login attempts. Please try again later.',
      );
    }

    if (code == 'RATE_LIMIT_EXCEEDED' || statusCode == 429) {
      return AuthApiException(
        type: AuthErrorType.rateLimited,
        code: code,
        statusCode: statusCode,
        message: serverMessage ??
            'Too many login requests. Please wait a minute before retrying.',
      );
    }

    if (code == 'VALIDATION_ERROR' || statusCode == 422) {
      final firstFieldError = fieldErrors.values
          .expand((list) => list)
          .cast<String?>()
          .firstWhere((msg) => msg != null && msg.isNotEmpty, orElse: () => null);
      return AuthApiException(
        type: AuthErrorType.validationError,
        code: code,
        statusCode: statusCode,
        fieldErrors: fieldErrors,
        message:
            firstFieldError ?? serverMessage ?? 'Please check your input.',
      );
    }

    return AuthApiException(
      type: AuthErrorType.serverError,
      code: code,
      statusCode: statusCode,
      message: serverMessage ?? 'Login failed (HTTP $statusCode).',
    );
  }

  /// Revokes the current device's Sanctum access token via `POST /api/v1/auth/logout`.
  Future<LogoutApiOutcome> logout({required String accessToken}) async {
    final baseUrl = _baseUrlResolver().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/auth/logout');

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer ${accessToken.trim()}',
              'X-Client-Version': 'flutter-mobile/1.0.0',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AuthApiException(
        type: AuthErrorType.timeout,
        code: 'REQUEST_TIMEOUT',
        message:
            'The server timed out while revoking your session. Please try again.',
      );
    } on SocketException {
      throw const AuthApiException(
        type: AuthErrorType.networkError,
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the server to revoke your session token. Please check your internet connection.',
      );
    } on http.ClientException catch (e) {
      throw AuthApiException(
        type: AuthErrorType.networkError,
        code: 'NETWORK_ERROR',
        message:
            'Network connection failed (${e.message}). Could not revoke token on server.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      String serverMsg = 'Logged out successfully.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['message'] is String) {
          serverMsg = decoded['message'] as String;
        }
      } catch (_) {}
      return LogoutApiOutcome(
        revokedOnServer: true,
        alreadyExpired: false,
        message: serverMsg,
      );
    }

    if (response.statusCode == 401) {
      return const LogoutApiOutcome(
        revokedOnServer: true,
        alreadyExpired: true,
        message: 'Your session had already expired. Signed out locally.',
      );
    }

    if (response.statusCode == 403) {
      return const LogoutApiOutcome(
        revokedOnServer: true,
        alreadyExpired: true,
        message: 'Account session is no longer active. Signed out locally.',
      );
    }

    throw AuthApiException(
      type: AuthErrorType.serverError,
      code: 'LOGOUT_FAILED',
      statusCode: response.statusCode,
      message:
          'Server could not complete logout (HTTP ${response.statusCode}). Please try again.',
    );
  }

  /// Validates an existing Sanctum Bearer token via `GET /api/v1/auth/session-check`.
  Future<AuthUser> checkSession({required String accessToken}) async {
    final baseUrl = _baseUrlResolver().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/auth/session-check');

    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer ${accessToken.trim()}',
              'X-Client-Version': 'flutter-mobile/1.0.0',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AuthApiException(
        type: AuthErrorType.timeout,
        code: 'REQUEST_TIMEOUT',
        message:
            'Session verification timed out. Please check your connection and retry.',
      );
    } on SocketException {
      throw const AuthApiException(
        type: AuthErrorType.networkError,
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the newsroom server to verify your session. Please check your connection.',
      );
    } on http.ClientException catch (e) {
      throw AuthApiException(
        type: AuthErrorType.networkError,
        code: 'NETWORK_ERROR',
        message:
            'Network connection failed (${e.message}). Please check your connection and retry.',
      );
    }

    Map<String, dynamic> bodyJson = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        bodyJson = decoded;
      }
    } catch (_) {}

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        bodyJson['success'] == true &&
        bodyJson['data'] is Map<String, dynamic>) {
      return AuthUser.fromJson(bodyJson['data'] as Map<String, dynamic>);
    }

    final errorObj = bodyJson['error'];
    final code = errorObj is Map<String, dynamic>
        ? (errorObj['code'] as String? ?? 'AUTH_ERROR')
        : 'AUTH_ERROR';
    final serverMessage = errorObj is Map<String, dynamic>
        ? (errorObj['message'] as String?)
        : null;

    if (response.statusCode == 401 || code == 'UNAUTHENTICATED') {
      throw AuthApiException(
        type: AuthErrorType.unauthenticated,
        code: 'UNAUTHENTICATED',
        statusCode: response.statusCode,
        message: serverMessage ?? 'Your session has expired. Please sign in again.',
      );
    }

    if (code == 'ACCOUNT_SUSPENDED') {
      throw AuthApiException(
        type: AuthErrorType.accountSuspended,
        code: code,
        statusCode: response.statusCode,
        message: serverMessage ??
            'Your account has been suspended. Please contact a newsroom administrator.',
      );
    }

    if (code == 'ACCOUNT_INACTIVE' || response.statusCode == 403) {
      throw AuthApiException(
        type: AuthErrorType.accountInactive,
        code: code,
        statusCode: response.statusCode,
        message: serverMessage ?? 'Your account is no longer active.',
      );
    }

    throw AuthApiException(
      type: AuthErrorType.serverError,
      code: code,
      statusCode: response.statusCode,
      message: serverMessage ??
          'Unable to verify session (HTTP ${response.statusCode}). Please retry.',
    );
  }
}

