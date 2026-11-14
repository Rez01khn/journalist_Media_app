import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/pending_media_registration.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite repository for storing and managing pending media registrations
/// that need to be synchronized with the Laravel News Media Metadata API.
class SqlitePendingMediaRepository {
  final DatabaseService _dbService;

  SqlitePendingMediaRepository([DatabaseService? dbService])
      : _dbService = dbService ?? DatabaseService();

  /// Saves or updates a pending media registration record.
  Future<void> savePendingMedia(PendingMediaRegistration record) async {
    final db = await _dbService.database;
    await db.insert(
      DatabaseService.tablePendingMediaRegistrations,
      record.toSqliteRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all records with status 'pending' eligible for registration retry.
  Future<List<PendingMediaRegistration>> getPendingMedia() async {
    final db = await _dbService.database;
    final results = await db.query(
      DatabaseService.tablePendingMediaRegistrations,
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'datetime(created_at) ASC',
    );
    return results.map(PendingMediaRegistration.fromSqliteRow).toList();
  }

  /// Retrieves all media registration records associated with a specific server news ID.
  Future<List<PendingMediaRegistration>> getRecordsForNews(
    String serverNewsId,
  ) async {
    final db = await _dbService.database;
    final results = await db.query(
      DatabaseService.tablePendingMediaRegistrations,
      where: 'server_news_id = ?',
      whereArgs: [serverNewsId],
      orderBy: 'datetime(created_at) ASC',
    );
    return results.map(PendingMediaRegistration.fromSqliteRow).toList();
  }

  /// Marks a record as successfully registered on the server.
  Future<void> markRegistered({
    required String id,
    required String serverMediaId,
  }) async {
    final db = await _dbService.database;
    await db.update(
      DatabaseService.tablePendingMediaRegistrations,
      {
        'status': 'registered',
        'server_media_id': serverMediaId,
        'error_message': null,
        'last_attempted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks a record as failed with an error message, incrementing retry count.
  Future<void> markFailed({
    required String id,
    required String errorMessage,
    bool isPermanent = false,
  }) async {
    final db = await _dbService.database;
    final existing = await db.query(
      DatabaseService.tablePendingMediaRegistrations,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final retryCount = existing.isNotEmpty
        ? (existing.first['retry_count'] as int? ?? 0) + 1
        : 1;

    await db.update(
      DatabaseService.tablePendingMediaRegistrations,
      {
        'status': isPermanent ? 'failed' : 'pending',
        'error_message': errorMessage,
        'last_attempted_at': DateTime.now().toIso8601String(),
        'retry_count': retryCount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Removes a pending media registration record.
  Future<void> deleteRecord(String id) async {
    final db = await _dbService.database;
    await db.delete(
      DatabaseService.tablePendingMediaRegistrations,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
