import 'dart:convert';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/repositories/news_repository.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite repository for locally persisting submitted news stories,
/// including server-assigned ID, tracking code, UUID, and submission status.
class SqliteSubmittedNewsRepository implements NewsRepository {
  final DatabaseService _dbService;

  SqliteSubmittedNewsRepository([DatabaseService? dbService])
      : _dbService = dbService ?? DatabaseService();

  /// Persists a successfully submitted news story to local SQLite storage,
  /// reconciling with existing local records to strictly prevent duplicates.
  Future<void> saveSubmittedNews(News news, {String? clientDraftUuid}) async {
    final db = await _dbService.database;

    // Check if matching row exists by id, server_id, or tracking_code
    String targetId = news.id;
    String? existingDraftUuid = clientDraftUuid;
    final existing = await db.query(
      DatabaseService.tableSubmittedNews,
      where:
          'id = ? OR server_id = ? OR (tracking_code = ? AND tracking_code != "REP-000" AND tracking_code != "")',
      whereArgs: [news.id, news.id, news.trackingCode],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      targetId = existing.first['id'] as String;
      existingDraftUuid ??= existing.first['client_draft_uuid'] as String?;
    }

    final row = <String, dynamic>{
      'id': targetId,
      'server_id': news.id,
      'server_uuid': news.id,
      'tracking_code': news.trackingCode,
      'reporter_id': news.reporterId,
      'headline': news.headline,
      'category': news.category,
      'location': news.location,
      'incident_details': news.incidentDetails,
      'status': news.status.toValue(),
      'submitted_at': news.submittedAt.toIso8601String(),
      'client_draft_uuid': existingDraftUuid,
      'media_attachments': jsonEncode(
        news.mediaAttachments.map((m) => m.toJson()).toList(),
      ),
      'voice_dispatch':
          news.voiceDispatch != null ? jsonEncode(news.voiceDispatch!.toJson()) : null,
      'is_ai_assisted': news.isAiAssisted ? 1 : 0,
      'media_registration_status': news.mediaRegistrationStatus.toValue(),
    };

    try {
      await db.insert(
        DatabaseService.tableSubmittedNews,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Graceful fallback if media_registration_status column is absent in legacy test db
      final fallbackRow = Map<String, dynamic>.from(row)
        ..remove('media_registration_status');
      await db.insert(
        DatabaseService.tableSubmittedNews,
        fallbackRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Retrieves all submitted news stories for the specified reporter.
  Future<List<News>> getAllSubmittedNews({required String reporterId}) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      DatabaseService.tableSubmittedNews,
      where: 'reporter_id = ?',
      whereArgs: [reporterId],
      orderBy: 'datetime(submitted_at) DESC',
    );

    return results.map(_fromSqliteRow).toList();
  }

  /// Retrieves a single submitted news story by ID.
  Future<News?> getSubmittedNewsById(String newsId) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      DatabaseService.tableSubmittedNews,
      where: 'id = ? OR server_id = ? OR tracking_code = ?',
      whereArgs: [newsId, newsId, newsId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromSqliteRow(results.first);
  }

  News _fromSqliteRow(Map<String, dynamic> row) {
    List<NewsMedia> media = [];
    if (row['media_attachments'] != null &&
        (row['media_attachments'] as String).isNotEmpty) {
      try {
        final decoded =
            jsonDecode(row['media_attachments'] as String) as List<dynamic>;
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
        final decoded =
            jsonDecode(row['voice_dispatch'] as String) as Map<String, dynamic>;
        voice = NewsMedia.fromJson(decoded);
      } catch (_) {
        voice = null;
      }
    }

    return News(
      id: row['server_id'] as String? ?? row['id'] as String,
      trackingCode: row['tracking_code'] as String? ?? 'REP-000',
      reporterId: row['reporter_id'] as String? ?? 'user-001',
      reporterName: '',
      headline: row['headline'] as String? ?? '',
      category: row['category'] as String? ?? '',
      location: row['location'] as String? ?? '',
      incidentDetails: row['incident_details'] as String? ?? '',
      status: NewsStatus.fromString(row['status'] as String? ?? 'submitted'),
      mediaAttachments: media,
      voiceDispatch: voice,
      isAiAssisted: (row['is_ai_assisted'] as int? ?? 0) == 1,
      mediaRegistrationStatus: MediaRegistrationStatus.fromString(
        row['media_registration_status'] as String?,
      ),
      submittedAt: row['submitted_at'] != null
          ? DateTime.parse(row['submitted_at'] as String)
          : DateTime.now(),
    );
  }

  /// Updates media registration status and attachment metadata for an existing submitted news story.
  Future<void> updateMediaRegistrationStatus({
    required String newsId,
    required MediaRegistrationStatus status,
    required List<NewsMedia> mediaAttachments,
    NewsMedia? voiceDispatch,
  }) async {
    final db = await _dbService.database;
    await db.update(
      DatabaseService.tableSubmittedNews,
      {
        'media_registration_status': status.toValue(),
        'media_attachments': jsonEncode(
          mediaAttachments.map((m) => m.toJson()).toList(),
        ),
        'voice_dispatch':
          voiceDispatch != null ? jsonEncode(voiceDispatch.toJson()) : null,
      },
      where: 'id = ? OR server_id = ?',
      whereArgs: [newsId, newsId],
    );
  }

  @override
  Future<List<News>> getReporterNews({
    required String reporterId,
    NewsStatus? statusFilter,
  }) async {
    final all = await getAllSubmittedNews(reporterId: reporterId);
    if (statusFilter == null) return all;
    return all.where((n) => n.status == statusFilter).toList();
  }

  @override
  Future<News?> getNewsById(String newsId) => getSubmittedNewsById(newsId);

  @override
  Future<Map<NewsStatus, int>> getNewsStatusCounts({
    required String reporterId,
  }) async {
    final all = await getAllSubmittedNews(reporterId: reporterId);
    final counts = <NewsStatus, int>{
      NewsStatus.draft: 0,
      NewsStatus.pending: 0,
      NewsStatus.underReview: 0,
      NewsStatus.correctionRequested: 0,
      NewsStatus.approved: 0,
      NewsStatus.published: 0,
      NewsStatus.rejected: 0,
    };
    for (final item in all) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    return counts;
  }

  /// Bulk saves a list of news items (e.g. after fetching from backend).
  Future<void> saveAll(List<News> list) async {
    for (final news in list) {
      await saveSubmittedNews(news);
    }
  }
}
