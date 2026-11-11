import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/services/draft_sync_service.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TASK 04.1 — Camera & Gallery Integration Tests', () {
    late Directory tempDir;
    late MockDraftRepository mockDraftRepo;
    late MockGoogleDriveRepository mockDriveRepo;
    late ProviderContainer container;
    late DraftSyncService syncService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('photo_test_');
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
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('1. Local Photo Persistence: Copies file to managed storage', () async {
      final mediaStorage = MediaStorageService();
      final sourceFile = File('${tempDir.path}/raw_spot_photo.jpg');
      await sourceFile.writeAsString('fake_image_bytes_12345');

      final persisted = await mediaStorage.persistDraftPhoto(
        sourceFile: sourceFile,
        draftId: 'draft_test_001',
      );

      expect(persisted.existsSync(), isTrue);
      expect(persisted.path, isNot(equals(sourceFile.path)));
      expect(await persisted.readAsString(), equals('fake_image_bytes_12345'));

      // Test safe deletion
      await mediaStorage.deleteLocalMedia(persisted.path);
      expect(persisted.existsSync(), isFalse);
    });

    test('2. Automatic Photo Upload: Syncs attached photos to Google Drive', () async {
      // Connect Drive in state
      container.read(googleDriveStateProvider.notifier).state = const GoogleDriveState(
        isConnected: true,
        accountEmail: 'reporter@test.com',
        folderId: 'folder_123',
      );

      final photoFile = File('${tempDir.path}/photo1.jpg');
      await photoFile.writeAsString('bytes_photo_1');

      final initialMedia = NewsMedia(
        id: 'media_1',
        fileName: 'photo1.jpg',
        localFilePath: photoFile.path,
        mimeType: 'image/jpeg',
        mediaType: MediaType.image,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_photo_1',
        reporterId: 'user-001',
        headline: 'Fire in Karwan Bazar',
        category: 'Disaster',
        location: 'Karwan Bazar, Dhaka',
        incidentDetails: 'Fire broke out in market complex.',
        mediaAttachments: [initialMedia],
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);

      final synced = await syncService.syncDraft(draft);

      expect(synced.driveSyncStatus, equals(DraftSyncStatus.synced));

      // Check media updated with Drive file ID
      final updatedDraft = await mockDraftRepo.getDraftById('draft_photo_1');
      expect(updatedDraft, isNotNull);
      expect(updatedDraft!.mediaAttachments.length, equals(1));
      final syncedMedia = updatedDraft.mediaAttachments.first;
      expect(syncedMedia.isUploadedToDrive, isTrue);
      expect(syncedMedia.driveFileId, isNotNull);

      // Local file is NOT deleted after upload
      expect(photoFile.existsSync(), isTrue);
    });

    test('3. Duplicate Upload Prevention: Preserves driveFileId and skips already uploaded photos', () async {
      container.read(googleDriveStateProvider.notifier).state = const GoogleDriveState(
        isConnected: true,
        accountEmail: 'reporter@test.com',
        folderId: 'folder_123',
      );

      final photoFile = File('${tempDir.path}/photo2.jpg');
      await photoFile.writeAsString('bytes_photo_2');

      final alreadyUploadedMedia = NewsMedia(
        id: 'media_2',
        fileName: 'photo2.jpg',
        localFilePath: photoFile.path,
        driveFileId: 'existing_drive_id_999',
        mimeType: 'image/jpeg',
        mediaType: MediaType.image,
        isUploadedToDrive: true,
        reporterGoogleAccountEmail: 'reporter@test.com',
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_photo_2',
        reporterId: 'user-001',
        headline: 'Follow up: Karwan Bazar Fire Under Control',
        category: 'Disaster',
        location: 'Karwan Bazar, Dhaka',
        incidentDetails: 'Fire service extinguished flames.',
        mediaAttachments: [alreadyUploadedMedia],
        driveFolderId: 'existing_news_folder_2',
        driveFileId: 'drive_draft_photo_2',
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);

      await syncService.syncDraft(draft);

      final fetched = await mockDraftRepo.getDraftById('draft_photo_2');
      expect(fetched!.mediaAttachments.first.driveFileId, equals('existing_drive_id_999'));
    });

    test('4. Offline Attachment Durability: Stored safely in SQLite when offline and retried on reconnect', () async {
      // Disconnected Drive
      container.read(googleDriveStateProvider.notifier).state = const GoogleDriveState(
        isConnected: false,
      );

      final photoFile = File('${tempDir.path}/offline_photo.jpg');
      await photoFile.writeAsString('offline_bytes');

      final media = NewsMedia(
        id: 'media_offline',
        fileName: 'offline_photo.jpg',
        localFilePath: photoFile.path,
        mimeType: 'image/jpeg',
        mediaType: MediaType.image,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_offline',
        reporterId: 'user-001',
        headline: 'Bridge Collapses in Sunamganj',
        category: 'Accident',
        location: 'Sunamganj',
        incidentDetails: 'Remote area communication severed.',
        mediaAttachments: [media],
        lastSavedAt: DateTime.now(),
      );

      final offlineResult = await syncService.syncDraft(draft);
      expect(offlineResult.driveSyncStatus, equals(DraftSyncStatus.pending));
      expect(photoFile.existsSync(), isTrue);

      // Verify repository state
      final storedDraft = await mockDraftRepo.getDraftById('draft_offline');
      expect(storedDraft!.mediaAttachments.length, equals(1));
      expect(storedDraft.mediaAttachments.first.isUploadedToDrive, isFalse);

      // Now restore connection
      container.read(googleDriveStateProvider.notifier).state = const GoogleDriveState(
        isConnected: true,
        accountEmail: 'reporter@test.com',
        folderId: 'folder_123',
      );

      // Retry pending sync
      await syncService.syncDraft(storedDraft);

      final reconnectedDraft = await mockDraftRepo.getDraftById('draft_offline');
      expect(reconnectedDraft!.driveSyncStatus, equals(DraftSyncStatus.synced));
      expect(reconnectedDraft.mediaAttachments.first.isUploadedToDrive, isTrue);
      expect(reconnectedDraft.mediaAttachments.first.driveFileId, isNotNull);
    });

    test('5. Photo Limits & Integrity: Does not delete local photos until confirmed', () async {
      final photoFile = File('${tempDir.path}/photo_keep.jpg');
      await photoFile.writeAsString('keep_bytes');

      final media = NewsMedia(
        id: 'media_keep',
        fileName: 'photo_keep.jpg',
        localFilePath: photoFile.path,
        mimeType: 'image/jpeg',
        mediaType: MediaType.image,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      container.read(googleDriveStateProvider.notifier).state = const GoogleDriveState(
        isConnected: true,
        accountEmail: 'reporter@test.com',
        folderId: 'folder_123',
      );

      final draft = NewsDraft(
        id: 'draft_photo_limit',
        reporterId: 'user-001',
        headline: 'Field Investigation',
        category: 'General',
        location: 'Test Location',
        incidentDetails: 'Details',
        mediaAttachments: [media],
        lastSavedAt: DateTime.now(),
      );

      await syncService.syncDraft(draft);

      // Local photo MUST still exist safely
      expect(photoFile.existsSync(), isTrue);
    });

    test(
        '6. News Folder Hierarchy: Creates folder named after News Title inside App Folder and renames on title edit',
        () async {
      container.read(googleDriveStateProvider.notifier).state =
          const GoogleDriveState(
        isConnected: true,
        accountEmail: 'reporter@test.com',
        folderId: 'app_folder_root',
        folderName: 'Journalist App',
      );

      final photoFile = File('${tempDir.path}/port_photo.jpg');
      await photoFile.writeAsString('port_image_bytes');

      final media = NewsMedia(
        id: 'media_port_1',
        fileName: 'port_photo.jpg',
        localFilePath: photoFile.path,
        mimeType: 'image/jpeg',
        mediaType: MediaType.image,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_folder_hierarchy',
        reporterId: 'user-001',
        headline: 'Chittagong Port Terminal Expansion',
        category: 'Economy',
        location: 'Chattogram',
        incidentDetails: 'New container terminal opened.',
        mediaAttachments: [media],
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);
      final synced = await syncService.syncDraft(draft);

      expect(synced.driveFolderId, isNotNull);
      expect(
        mockDriveRepo.newsFolders[synced.driveFolderId],
        equals('Chittagong Port Terminal Expansion'),
      );

      // Edit the News Title and sync again — should rename the existing folder without creating a duplicate folder
      final renamedDraft = synced.copyWith(
        headline: 'Chittagong Port Terminal Expansion Phase 2',
        isSyncedWithDrive: false,
        driveSyncStatus: DraftSyncStatus.pending,
      );
      await mockDraftRepo.saveDraft(renamedDraft);
      final resynced = await syncService.syncDraft(renamedDraft);

      expect(resynced.driveFolderId, equals(synced.driveFolderId));
      expect(mockDriveRepo.newsFolders.length, equals(1));
      expect(
        mockDriveRepo.newsFolders[resynced.driveFolderId],
        equals('Chittagong Port Terminal Expansion Phase 2'),
      );
    });
  });
}
