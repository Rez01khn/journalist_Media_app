import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/services/draft_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDraftRepository mockDraftRepo;
  late MockGoogleDriveRepository mockDriveRepo;
  late ProviderContainer container;
  late DraftSyncService syncService;

  setUp(() {
    mockDraftRepo = MockDraftRepository();
    mockDraftRepo.clear();
    mockDriveRepo = MockGoogleDriveRepository();

    container = ProviderContainer(
      overrides: [
        draftRepositoryProvider.overrideWithValue(mockDraftRepo),
        googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
      ],
    );

    syncService = container.read(draftSyncServiceProvider);
  });

  tearDown(() {
    container.dispose();
  });

  group('TASK 03.1 — Automatic Google Drive Draft Sync Tests', () {
    test('1. Offline Saving First: Saves draft locally even if Drive is disconnected',
        () async {
      // Google Drive is NOT connected in state
      expect(container.read(googleDriveStateProvider).isConnected, isFalse);

      final draft = NewsDraft(
        id: 'draft-offline-1',
        reporterId: 'user-001',
        headline: 'Remote Field Investigation in Bandarban',
        category: 'Investigation',
        location: 'Bandarban Hills',
        incidentDetails: 'Intermittent signal in hill tracks...',
        lastSavedAt: DateTime.now(),
      );

      // Save locally first
      await mockDraftRepo.saveDraft(draft);

      // Run sync while disconnected
      final result = await syncService.syncDraft(draft);

      // Verify draft is stored locally in repository
      final saved = await mockDraftRepo.getDraftById('draft-offline-1');
      expect(saved, isNotNull);
      expect(saved!.headline, equals('Remote Field Investigation in Bandarban'));
      expect(saved.isSyncedWithDrive, isFalse);
      expect(saved.driveSyncStatus, equals(DraftSyncStatus.pending));
      expect(result.driveSyncStatus, equals(DraftSyncStatus.pending));
    });

    test('2. Automatic Sync: Uploads to Drive when reporter account is connected',
        () async {
      // Connect mock Google Drive
      await container
          .read(googleDriveStateProvider.notifier)
          .connectAccount(preferredEmail: 'reporter@gmail.com');
      expect(container.read(googleDriveStateProvider).isConnected, isTrue);

      final draft = NewsDraft(
        id: 'draft-online-1',
        reporterId: 'user-001',
        headline: 'Dhaka Airport Third Terminal Update',
        category: 'Infrastructure',
        location: 'Dhaka Airport',
        incidentDetails: 'Operational trials commenced today...',
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);

      // Sync draft
      final synced = await syncService.syncDraft(draft);

      expect(synced.isSyncedWithDrive, isTrue);
      expect(synced.driveSyncStatus, equals(DraftSyncStatus.synced));
      expect(synced.driveFileId, isNotNull);
      expect(synced.driveFileId, contains('drive-draft-'));

      // Check Drive repository has the file
      final driveFiles =
          await mockDriveRepo.listFiles(reporterGoogleEmail: 'reporter@gmail.com');
      expect(driveFiles.any((f) => f.driveFileId == synced.driveFileId), isTrue);
    });

    test(
        '3. Duplicate Prevention: Updating an existing draft updates Drive file without creating duplicates',
        () async {
      await container
          .read(googleDriveStateProvider.notifier)
          .connectAccount(preferredEmail: 'reporter@gmail.com');

      final initialDraft = NewsDraft(
        id: 'draft-stable-id',
        reporterId: 'user-001',
        headline: 'Initial Fact Finding Notes',
        category: 'Politics',
        location: 'Savar',
        incidentDetails: 'Initial notes from the ground.',
        lastSavedAt: DateTime(2026, 11, 8, 10, 0),
      );

      // First sync
      final firstSynced = await syncService.syncDraft(initialDraft);
      final initialDriveId = firstSynced.driveFileId;
      expect(initialDriveId, isNotNull);

      // Verify 1 file in Drive
      var files = await mockDriveRepo.listFiles(
          reporterGoogleEmail: 'reporter@gmail.com');
      expect(files.length, equals(1));

      // User edits the draft locally (2-second auto-save trigger)
      final editedDraft = firstSynced.copyWith(
        headline: 'Breaking: Updated Fact Finding with Official Confirmation',
        incidentDetails: 'Added official confirmation statements.',
        lastSavedAt: DateTime(2026, 11, 8, 10, 5),
        isSyncedWithDrive: false,
        driveSyncStatus: DraftSyncStatus.pending,
      );

      await mockDraftRepo.saveDraft(editedDraft);

      // Second sync
      final secondSynced = await syncService.syncDraft(editedDraft);

      // Verify the Drive file ID remained the same (updated, not duplicated)
      expect(secondSynced.driveFileId, equals(initialDriveId));
      expect(secondSynced.isSyncedWithDrive, isTrue);
      expect(secondSynced.driveSyncStatus, equals(DraftSyncStatus.synced));

      // Verify file count in Drive is STILL exactly 1
      files = await mockDriveRepo.listFiles(
          reporterGoogleEmail: 'reporter@gmail.com');
      expect(files.length, equals(1));
    });

    test(
        '4. Reconnection & Retry: Automatically syncs all pending drafts when Drive reconnects',
        () async {
      // Seed 2 pending offline drafts in repository
      final pending1 = NewsDraft(
        id: 'draft-pending-1',
        reporterId: 'user-001',
        headline: 'Pending Story 1',
        category: 'National',
        location: 'Khulna',
        incidentDetails: 'Offline notes 1',
        lastSavedAt: DateTime.now(),
        isSyncedWithDrive: false,
        driveSyncStatus: DraftSyncStatus.pending,
      );

      final pending2 = NewsDraft(
        id: 'draft-pending-2',
        reporterId: 'user-001',
        headline: 'Pending Story 2',
        category: 'Environment',
        location: 'Sundarbans',
        incidentDetails: 'Offline notes 2',
        lastSavedAt: DateTime.now(),
        isSyncedWithDrive: false,
        driveSyncStatus: DraftSyncStatus.pending,
      );

      await mockDraftRepo.saveDraft(pending1);
      await mockDraftRepo.saveDraft(pending2);

      // Verify pending count in repository
      final pendingBefore =
          await mockDraftRepo.getPendingSyncDrafts(reporterId: 'user-001');
      expect(pendingBefore.length, equals(2));

      // Connect Google Drive (automatically triggers syncAllPendingDrafts via background task)
      await container
          .read(googleDriveStateProvider.notifier)
          .connectAccount(preferredEmail: 'reporter@gmail.com');

      // Allow background microtask to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify no pending drafts left
      final pendingAfter =
          await mockDraftRepo.getPendingSyncDrafts(reporterId: 'user-001');
      expect(pendingAfter.isEmpty, isTrue);

      // Check both are marked synced
      final d1 = await mockDraftRepo.getDraftById('draft-pending-1');
      final d2 = await mockDraftRepo.getDraftById('draft-pending-2');
      expect(d1!.isSyncedWithDrive, isTrue);
      expect(d2!.isSyncedWithDrive, isTrue);
    });

    test('5. Editorial Safeguard: Sync never submits news for editorial review',
        () async {
      await container
          .read(googleDriveStateProvider.notifier)
          .connectAccount(preferredEmail: 'reporter@gmail.com');

      final draft = NewsDraft(
        id: 'draft-editorial-safety',
        reporterId: 'user-001',
        headline: 'Sensitive Investigative Report',
        category: 'National',
        location: 'Secret location',
        incidentDetails: 'Draft notes in progress...',
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);
      final synced = await syncService.syncDraft(draft);

      // Draft must remain a draft in SQLite, not submitted to editorial review
      expect(synced.isSyncedWithDrive, isTrue);
      final storedDraft =
          await mockDraftRepo.getDraftById('draft-editorial-safety');
      expect(storedDraft, isNotNull);
      // NewsDraft has no editorial submission status change
      expect(storedDraft!.headline, equals('Sensitive Investigative Report'));
    });
  });
}
