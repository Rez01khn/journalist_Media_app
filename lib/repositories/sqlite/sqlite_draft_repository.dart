import 'dart:convert';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/repositories/draft_repository.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite implementation of [DraftRepository] providing robust offline
/// persistence for field news stories.
class SqliteDraftRepository implements DraftRepository {
  final DatabaseService _dbService;

  SqliteDraftRepository([DatabaseService? dbService])
      : _dbService = dbService ?? DatabaseService();

  @override
  Future<List<NewsDraft>> getAllDrafts({required String reporterId}) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      DatabaseService.tableNewsDrafts,
      where: 'reporter_id = ?',
      whereArgs: [reporterId],
      orderBy: 'datetime(last_saved_at) DESC',
    );

    return results.map((row) => _fromSqliteRow(row)).toList();
  }

  @override
  Future<NewsDraft?> getDraftById(String draftId) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      DatabaseService.tableNewsDrafts,
      where: 'id = ?',
      whereArgs: [draftId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromSqliteRow(results.first);
  }

  /// Retrieves the single most recently edited draft for the reporter,
  /// used to restore work across app restarts.
  Future<NewsDraft?> getMostRecentDraft({required String reporterId}) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      DatabaseService.tableNewsDrafts,
      where: 'reporter_id = ?',
      whereArgs: [reporterId],
      orderBy: 'datetime(last_saved_at) DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromSqliteRow(results.first);
  }

  @override
  Future<void> saveDraft(NewsDraft draft) async {
    final db = await _dbService.database;
    final row = _toSqliteRow(draft);

    await db.insert(
      DatabaseService.tableNewsDrafts,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    final db = await _dbService.database;
    await db.delete(
      DatabaseService.tableNewsDrafts,
      where: 'id = ?',
      whereArgs: [draftId],
    );
  }

  @override
  Future<List<NewsDraft>> getPendingSyncDrafts({required String reporterId}) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      DatabaseService.tableNewsDrafts,
      where: 'reporter_id = ? AND (is_synced_with_drive = 0 OR drive_sync_status != ?)',
      whereArgs: [reporterId, DraftSyncStatus.synced.name],
      orderBy: 'datetime(last_saved_at) DESC',
    );

    return results.map((row) => _fromSqliteRow(row)).toList();
  }

  // --- Serialization Helpers ---

  Map<String, dynamic> _toSqliteRow(NewsDraft draft) {
    return {
      'id': draft.id,
      'reporter_id': draft.reporterId,
      'headline': draft.headline,
      'category': draft.category,
      'location': draft.location,
      'incident_details': draft.incidentDetails,
      'media_attachments': jsonEncode(
        draft.mediaAttachments.map((m) => m.toJson()).toList(),
      ),
      'voice_dispatch':
          draft.voiceDispatch != null ? jsonEncode(draft.voiceDispatch!.toJson()) : null,
      'ai_assisted_headline': draft.aiAssistedHeadline,
      'ai_assisted_body': draft.aiAssistedBody,
      'is_ai_assisted': draft.isAiAssisted ? 1 : 0,
      'last_saved_at': draft.lastSavedAt.toIso8601String(),
      'is_synced_with_drive': draft.isSyncedWithDrive ? 1 : 0,
      'drive_folder_id': draft.driveFolderId,
      'drive_file_id': draft.driveFileId,
      'drive_sync_status': draft.driveSyncStatus.name,
      'last_synced_at': draft.lastSyncedAt?.toIso8601String(),
      'sync_error_message': draft.syncErrorMessage,
    };
  }

  NewsDraft _fromSqliteRow(Map<String, dynamic> row) {
    List<NewsMedia> media = [];
    if (row['media_attachments'] != null &&
        (row['media_attachments'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(row['media_attachments'] as String) as List<dynamic>;
        media = decoded
            .map((item) => NewsMedia.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        media = [];
      }
    }

    NewsMedia? voice;
    if (row['voice_dispatch'] != null &&
        (row['voice_dispatch'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(row['voice_dispatch'] as String) as Map<String, dynamic>;
        voice = NewsMedia.fromJson(decoded);
      } catch (_) {
        voice = null;
      }
    }

    final isSynced = (row['is_synced_with_drive'] as int? ?? 0) == 1;
    final syncStatusStr = row['drive_sync_status'] as String?;
    final syncStatus = syncStatusStr != null
        ? DraftSyncStatus.values.firstWhere(
            (e) => e.name == syncStatusStr,
            orElse: () =>
                isSynced ? DraftSyncStatus.synced : DraftSyncStatus.pending,
          )
        : (isSynced ? DraftSyncStatus.synced : DraftSyncStatus.pending);

    return NewsDraft(
      id: row['id'] as String,
      reporterId: row['reporter_id'] as String,
      headline: row['headline'] as String? ?? '',
      category: row['category'] as String? ?? '',
      location: row['location'] as String? ?? '',
      incidentDetails: row['incident_details'] as String? ?? '',
      mediaAttachments: media,
      voiceDispatch: voice,
      aiAssistedHeadline: row['ai_assisted_headline'] as String?,
      aiAssistedBody: row['ai_assisted_body'] as String?,
      isAiAssisted: (row['is_ai_assisted'] as int? ?? 0) == 1,
      lastSavedAt: DateTime.parse(row['last_saved_at'] as String),
      isSyncedWithDrive: isSynced || syncStatus == DraftSyncStatus.synced,
      driveFolderId: row['drive_folder_id'] as String?,
      driveFileId: row['drive_file_id'] as String?,
      driveSyncStatus: syncStatus,
      lastSyncedAt: row['last_synced_at'] != null
          ? DateTime.tryParse(row['last_synced_at'] as String)
          : null,
      syncErrorMessage: row['sync_error_message'] as String?,
    );
  }
}

