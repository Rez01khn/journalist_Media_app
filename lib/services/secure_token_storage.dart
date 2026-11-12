import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:journalist_app_1/models/auth_session.dart';

/// Abstraction over platform-encrypted credential storage (Android Keystore / iOS Keychain).
abstract class SecureTokenStorage {
  Future<void> saveSession(AuthSession session);
  Future<AuthSession?> readSession();
  Future<String?> readAccessToken();
  Future<void> clearSession();
  Future<String> getOrCreateDeviceId();
  Future<void> saveLinkedGoogleDriveEmail({
    required String userKey,
    required String googleEmail,
  });
  Future<String?> readLinkedGoogleDriveEmail({required String userKey});
  Future<void> clearLinkedGoogleDriveEmail({required String userKey});
}

/// Production implementation backed by [FlutterSecureStorage].
class FlutterSecureTokenStorage implements SecureTokenStorage {
  static const String _tokenKey = 'journalist_sanctum_access_token';
  static const String _sessionMetaKey = 'journalist_sanctum_session_meta';
  static const String _deviceIdKey = 'journalist_device_id';
  static const String _driveEmailPrefix = 'journalist_linked_drive_email_';

  final FlutterSecureStorage _storage;

  const FlutterSecureTokenStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  @override
  Future<void> saveSession(AuthSession session) async {
    await _storage.write(key: _tokenKey, value: session.accessToken);
    await _storage.write(
      key: _sessionMetaKey,
      value: jsonEncode(session.toMetadataJson()),
    );
  }

  @override
  Future<AuthSession?> readSession() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final metaRaw = await _storage.read(key: _sessionMetaKey);
      if (token == null || token.trim().isEmpty || metaRaw == null) {
        return null;
      }

      final decoded = jsonDecode(metaRaw);
      if (decoded is! Map<String, dynamic>) {
        await clearSession();
        return null;
      }

      final session = AuthSession.fromStored(
        accessToken: token.trim(),
        metadataJson: decoded,
      );

      if (session.isExpired) {
        await clearSession();
        return null;
      }

      return session;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readAccessToken() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.trim().isEmpty) return null;
      return token.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _sessionMetaKey);
  }

  @override
  Future<String> getOrCreateDeviceId() async {
    try {
      final existing = await _storage.read(key: _deviceIdKey);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing.trim();
      }
    } catch (_) {
      // Generate a fresh device identifier if secure storage read fails.
    }

    final random = Random.secure();
    final hexBytes = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final newId = 'dev_$hexBytes';

    try {
      await _storage.write(key: _deviceIdKey, value: newId);
    } catch (_) {
      // Ignore write failures in test environments.
    }
    return newId;
  }

  String _driveKeyForUser(String userKey) {
    final sanitized = userKey.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '_',
    );
    return '$_driveEmailPrefix${sanitized.isEmpty ? 'default' : sanitized}';
  }

  bool get _isFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Future<void> saveLinkedGoogleDriveEmail({
    required String userKey,
    required String googleEmail,
  }) async {
    if (_isFlutterTest) return;
    try {
      await _storage.write(
        key: _driveKeyForUser(userKey),
        value: googleEmail.trim(),
      );
    } catch (_) {}
  }

  @override
  Future<String?> readLinkedGoogleDriveEmail({required String userKey}) async {
    if (_isFlutterTest) return null;
    try {
      final email = await _storage.read(key: _driveKeyForUser(userKey));
      if (email == null || email.trim().isEmpty) return null;
      return email.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearLinkedGoogleDriveEmail({required String userKey}) async {
    if (_isFlutterTest) return;
    try {
      await _storage.delete(key: _driveKeyForUser(userKey));
    } catch (_) {}
  }
}

