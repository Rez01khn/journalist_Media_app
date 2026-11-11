import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_draft_repository.dart';
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
}

