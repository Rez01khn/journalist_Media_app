import 'package:journalist_app_1/models/reporter.dart';

/// Abstract contract for authentication and reporter session management.
///
/// Designed to interface with the independent Laravel Sanctum / JWT API in Phase 2.
abstract class AuthRepository {
  /// Stream of authentication state changes
  Stream<Reporter?> get authStateChanges;

  /// Retrieves the currently authenticated reporter, or null if unauthenticated.
  Future<Reporter?> getCurrentReporter();

  /// Authenticates with the independent API using reporter credentials.
  Future<bool> login({
    required String emailOrUsername,
    required String password,
  });

  /// Terminates the current session and clears local tokens.
  Future<void> logout();
}

