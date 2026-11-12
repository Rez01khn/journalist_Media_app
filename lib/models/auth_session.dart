import 'package:journalist_app_1/models/auth_user.dart';

/// Represents an authenticated Sanctum API session stored securely on device.
class AuthSession {
  final String accessToken;
  final String tokenType;
  final DateTime? expiresAt;
  final List<String> abilities;
  final AuthUser user;

  const AuthSession({
    required this.accessToken,
    this.tokenType = 'Bearer',
    this.expiresAt,
    this.abilities = const [],
    required this.user,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());

  /// Parses the `data` object returned by `POST /api/v1/auth/login`.
  factory AuthSession.fromLoginDataJson(Map<String, dynamic> data) {
    final token = (data['access_token'] as String? ?? '').trim();
    if (token.isEmpty) {
      throw const FormatException('Missing access_token in login response.');
    }

    final userRaw = data['user'];
    if (userRaw is! Map<String, dynamic>) {
      throw const FormatException('Missing user object in login response.');
    }

    final expiresAtRaw = data['expires_at'] as String?;
    final parsedExpiry = expiresAtRaw != null && expiresAtRaw.isNotEmpty
        ? DateTime.tryParse(expiresAtRaw)?.toUtc()
        : null;

    final rawAbilities = data['abilities'];
    final abilities = rawAbilities is List
        ? rawAbilities.whereType<String>().toList(growable: false)
        : const <String>[];

    return AuthSession(
      accessToken: token,
      tokenType: data['token_type'] as String? ?? 'Bearer',
      expiresAt: parsedExpiry,
      abilities: abilities,
      user: AuthUser.fromJson(userRaw),
    );
  }

  /// Non-secret metadata persisted separately from the bearer token.
  Map<String, dynamic> toMetadataJson() {
    return {
      'token_type': tokenType,
      'expires_at': expiresAt?.toIso8601String(),
      'abilities': abilities,
      'user': user.toJson(),
    };
  }

  factory AuthSession.fromStored({
    required String accessToken,
    required Map<String, dynamic> metadataJson,
  }) {
    final expiresAtRaw = metadataJson['expires_at'] as String?;
    final rawAbilities = metadataJson['abilities'];
    final userRaw = metadataJson['user'];
    if (userRaw is! Map<String, dynamic>) {
      throw const FormatException('Corrupted stored session user metadata.');
    }

    return AuthSession(
      accessToken: accessToken,
      tokenType: metadataJson['token_type'] as String? ?? 'Bearer',
      expiresAt: expiresAtRaw != null && expiresAtRaw.isNotEmpty
          ? DateTime.tryParse(expiresAtRaw)?.toUtc()
          : null,
      abilities: rawAbilities is List
          ? rawAbilities.whereType<String>().toList(growable: false)
          : const <String>[],
      user: AuthUser.fromJson(userRaw),
    );
  }
}

