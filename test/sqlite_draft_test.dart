import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_draft_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_submitted_news_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService dbService;
  late SqliteDraftRepository draftRepo;

  setUp(() async {
    // Open in-memory SQLite database for testing
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE ${DatabaseService.tableNewsDrafts} (
        id TEXT PRIMARY KEY,
        reporter_id TEXT NOT NULL,
        headline TEXT,
        category TEXT,
        location TEXT,
        incident_details TEXT,
        media_attachments TEXT,
        voice_dispatch TEXT,
        ai_assisted_headline TEXT,
        ai_assisted_body TEXT,
        is_ai_assisted INTEGER DEFAULT 0,
        last_saved_at TEXT NOT NULL,
        is_synced_with_drive INTEGER DEFAULT 0,
        drive_folder_id TEXT,
        drive_file_id TEXT,
        drive_sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        sync_error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DatabaseService.tableSubmittedNews} (
        id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        server_uuid TEXT NOT NULL,
        tracking_code TEXT NOT NULL,
        reporter_id TEXT NOT NULL,
        headline TEXT NOT NULL,
        category TEXT,
        location TEXT,
        incident_details TEXT,
        status TEXT NOT NULL,
        submitted_at TEXT NOT NULL,
        client_draft_uuid TEXT,
        media_attachments TEXT,
        voice_dispatch TEXT,
        is_ai_assisted INTEGER DEFAULT 0,
        media_registration_status TEXT DEFAULT 'none'
      )
    ''');

    dbService = DatabaseService(db);
    draftRepo = SqliteDraftRepository(dbService);
  });

  tearDown(() async {
    await db.close();
  });

  group('SQLite Offline News Draft Tests', () {
    test('Save Draft inserts new record and retrieves it', () async {
      final draft = NewsDraft(
        id: 'draft-1',
        reporterId: 'user-001',
        headline: 'Flooding in Sylhet Lowlands',
        category: 'National',
        location: 'Sylhet',
        incidentDetails: 'Water levels exceeded danger marks in 3 upazilas...',
        lastSavedAt: DateTime(2026, 11, 8, 10, 0),
      );

      await draftRepo.saveDraft(draft);

      final retrieved = await draftRepo.getDraftById('draft-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.headline, equals('Flooding in Sylhet Lowlands'));
      expect(retrieved.category, equals('National'));
      expect(retrieved.location, equals('Sylhet'));
      expect(retrieved.incidentDetails, contains('danger marks'));
    });

    test('Auto-save updates existing draft with new content and timestamp', () async {
      final initialDraft = NewsDraft(
        id: 'draft-auto',
        reporterId: 'user-001',
        headline: 'Initial Headline',
        category: 'Politics',
        location: 'Dhaka',
        incidentDetails: 'Initial notes...',
        lastSavedAt: DateTime(2026, 11, 8, 10, 0),
      );

      await draftRepo.saveDraft(initialDraft);

      // Simulate auto-save after user types more information
      final updatedDraft = initialDraft.copyWith(
        headline: 'Updated Breaking Headline',
        incidentDetails: 'Updated breaking incident details...',
        lastSavedAt: DateTime(2026, 11, 8, 10, 5),
      );

      await draftRepo.saveDraft(updatedDraft);

      final allDrafts = await draftRepo.getAllDrafts(reporterId: 'user-001');
      expect(allDrafts.length, equals(1));
      expect(allDrafts.first.headline, equals('Updated Breaking Headline'));
      expect(allDrafts.first.incidentDetails, contains('Updated breaking'));
    });

    test('Draft list returns all drafts ordered by last_saved_at descending', () async {
      final draft1 = NewsDraft(
        id: 'draft-old',
        reporterId: 'user-001',
        headline: 'Older Story',
        category: 'Education',
        location: 'Rajshahi',
        incidentDetails: 'Old details',
        lastSavedAt: DateTime(2026, 11, 7, 14, 0),
      );

      final draft2 = NewsDraft(
        id: 'draft-new',
        reporterId: 'user-001',
        headline: 'Newer Breaking Story',
        category: 'Crime',
        location: 'Chattogram',
        incidentDetails: 'Newer details',
        lastSavedAt: DateTime(2026, 11, 8, 12, 0),
      );

      await draftRepo.saveDraft(draft1);
      await draftRepo.saveDraft(draft2);

      final drafts = await draftRepo.getAllDrafts(reporterId: 'user-001');
      expect(drafts.length, equals(2));
      // First item must be the most recently saved
      expect(drafts.first.id, equals('draft-new'));
      expect(drafts.last.id, equals('draft-old'));
    });

    test('Delete draft removes record from SQLite', () async {
      final draft = NewsDraft(
        id: 'draft-to-delete',
        reporterId: 'user-001',
        headline: 'Temporary draft',
        category: 'Sports',
        location: 'Mirpur',
        incidentDetails: 'Draft to discard',
        lastSavedAt: DateTime.now(),
      );

      await draftRepo.saveDraft(draft);
      var drafts = await draftRepo.getAllDrafts(reporterId: 'user-001');
      expect(drafts.length, equals(1));

      await draftRepo.deleteDraft('draft-to-delete');
      drafts = await draftRepo.getAllDrafts(reporterId: 'user-001');
      expect(drafts.isEmpty, isTrue);
    });

    test('Restore after app restart retrieves the single most recent draft', () async {
      final draftA = NewsDraft(
        id: 'draft-a',
        reporterId: 'user-001',
        headline: 'Earlier Story',
        category: 'Culture',
        location: 'Khulna',
        incidentDetails: 'Earlier details',
        lastSavedAt: DateTime(2026, 11, 8, 8, 0),
      );

      final draftB = NewsDraft(
        id: 'draft-b',
        reporterId: 'user-001',
        headline: 'Last In-Progress Field Dispatch',
        category: 'National',
        location: 'Motijheel',
        incidentDetails: 'Reporter was writing this before app closed...',
        lastSavedAt: DateTime(2026, 11, 8, 12, 30),
      );

      await draftRepo.saveDraft(draftA);
      await draftRepo.saveDraft(draftB);

      final restored = await draftRepo.getMostRecentDraft(reporterId: 'user-001');
      expect(restored, isNotNull);
      expect(restored!.id, equals('draft-b'));
      expect(restored.headline, equals('Last In-Progress Field Dispatch'));
    });
  });

  group('SQLite Submitted News Persistence Tests', () {
    test('saveSubmittedNews persists server ID, tracking code, status, and retrieves it', () async {
      final submittedRepo = SqliteSubmittedNewsRepository(dbService);

      final news = News(
        id: '101',
        trackingCode: 'REP-20261114-0101',
        reporterId: 'user-001',
        reporterName: 'Rezwan Karim',
        headline: 'High-Speed Rail Feasibility Study Approved',
        category: 'Transport',
        location: 'Dhaka',
        incidentDetails: 'The cabinet approved the feasibility study today.',
        status: NewsStatus.pending,
        submittedAt: DateTime(2026, 11, 14, 11, 0),
      );

      await submittedRepo.saveSubmittedNews(news, clientDraftUuid: 'uuid-1234');

      final list = await submittedRepo.getAllSubmittedNews(reporterId: 'user-001');
      expect(list.length, equals(1));
      expect(list.first.id, equals('101'));
      expect(list.first.trackingCode, equals('REP-20261114-0101'));
      expect(list.first.status, equals(NewsStatus.pending));
      expect(list.first.headline, equals('High-Speed Rail Feasibility Study Approved'));

      final single = await submittedRepo.getSubmittedNewsById('REP-20261114-0101');
      expect(single, isNotNull);
      expect(single!.id, equals('101'));

      // Test NewsRepository contract implementations
      final filteredList = await submittedRepo.getReporterNews(
        reporterId: 'user-001',
        statusFilter: NewsStatus.pending,
      );
      expect(filteredList.length, equals(1));

      final counts = await submittedRepo.getNewsStatusCounts(reporterId: 'user-001');
      expect(counts[NewsStatus.pending], equals(1));
      expect(counts[NewsStatus.approved], equals(0));
    });
  });
}

