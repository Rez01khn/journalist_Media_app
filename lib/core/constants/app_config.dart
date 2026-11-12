import 'dart:io';

import 'package:flutter/foundation.dart';

/// Application-wide runtime configuration.
class AppConfig {
  /// Web OAuth 2.0 Client ID created in Google Cloud Console.
  ///
  /// Required by Google Sign-In on Android as `serverClientId` to exchange
  /// tokens with Google Drive scopes (`drive.file`).
  ///
  /// NOTE: Only Client ID is used. NEVER store or request the Client Secret.
  static const String googleWebClientId =
      '614059180899-mle0dj2b39qnv1i5a57rgti9gcao63se.apps.googleusercontent.com';

  /// Optional compile-time override via `--dart-define=API_BASE_URL=...`.
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Laravel REST API v1 base URL.
  ///
  /// Uses Android emulator host-loopback (`10.0.2.2`) by default on Android,
  /// and `127.0.0.1` on Web/desktop/iOS simulators unless overridden via
  /// `--dart-define=API_BASE_URL=https://...`.
  static String get apiBaseUrl {
    if (_envApiBaseUrl.trim().isNotEmpty) {
      return _envApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api/v1';
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000/api/v1';
    }

    return 'http://127.0.0.1:8000/api/v1';
  }
}
