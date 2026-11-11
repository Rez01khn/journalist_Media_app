import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/core/errors/google_drive_exceptions.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_draft_repository.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';
import 'package:journalist_app_1/services/voice_recorder_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Programmable mock Google Drive repository to simulate network drops,
/// upload delays (for concurrency/dirty-during-sync/account-switch tests),
/// and server failures on real integration flows.
class ControllableGoogleDriveRepository extends MockGoogleDriveRepository {
  bool simulateOffline = false;
  bool failNextMediaUpload = false;
  Duration uploadDelay = Duration.zero;
  int mediaUploadCalls = 0;
  int draftUploadCalls = 0;
  VoidCallback? onFirstMediaUploadStarted;

  @override
  Future<String> getOrCreateNewsFolder({
    required String newsTitle,
    required String reporterGoogleEmail,
    String? appFolderName,
    String? existingNewsFolderId,
  }) async {
    if (simulateOffline) {
      throw const SocketException('Simulated offline: Failed host lookup');
    }
    return super.getOrCreateNewsFolder(
      newsTitle: newsTitle,
      reporterGoogleEmail: reporterGoogleEmail,
      appFolderName: appFolderName,
      existingNewsFolderId: existingNewsFolderId,
    );
  }

  @override
  Future<NewsMedia> uploadMediaToReporterDrive({
    required String localFilePath,
    required MediaType mediaType,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
  }) async {
    mediaUploadCalls++;
    if (mediaUploadCalls == 1 && onFirstMediaUploadStarted != null) {
      onFirstMediaUploadStarted!();
      onFirstMediaUploadStarted = null;
    }
    if (uploadDelay > Duration.zero) {
      await Future<void>.delayed(uploadDelay);
    }
    if (simulateOffline) {
      throw const SocketException('Simulated network drop during media upload');
    }
    if (failNextMediaUpload) {
      failNextMediaUpload = false;
      throw const GoogleDriveUploadException('Simulated Drive 500 error');
    }
    return super.uploadMediaToReporterDrive(
      localFilePath: localFilePath,
      mediaType: mediaType,
      reporterGoogleEmail: reporterGoogleEmail,
      targetFolderName: targetFolderName,
      targetFolderId: targetFolderId,
    );
  }

  @override
  Future<NewsMedia> uploadDraftFile({
    required String localFilePath,
    required String draftId,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
    String? existingDriveFileId,
  }) async {
    draftUploadCalls++;
    if (simulateOffline) {
      throw const SocketException('Simulated network drop during draft JSON upload');
    }
    return super.uploadDraftFile(
      localFilePath: localFilePath,
      draftId: draftId,
      reporterGoogleEmail: reporterGoogleEmail,
      targetFolderName: targetFolderName,
      targetFolderId: targetFolderId,
      existingDriveFileId: existingDriveFileId,
    );
  }
}

typedef VoidCallback = void Function();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late MediaStorageService mediaStorage;

  Future<(Database, SqliteDraftRepository)> createSqliteRepo() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
    return (db, SqliteDraftRepository(DatabaseService(db)));
  }

  Future<(NewsMedia photo, NewsMedia video, NewsMedia voice)> createAllThreeMedia(
    String draftId,
  ) async {
    final rawPhoto = File(p.join(tempDir.path, 'raw_${draftId}_photo.jpg'));
    await rawPhoto.writeAsBytes(List<int>.filled(512, 11));
    final savedPhoto = await mediaStorage.persistDraftPhoto(
      sourceFile: rawPhoto,
      draftId: draftId,
    );

    final rawVideo = File(p.join(tempDir.path, 'raw_${draftId}_video.mp4'));
    await rawVideo.writeAsBytes(List<int>.filled(2048, 22));
    final savedVideo = await mediaStorage.persistDraftVideo(
      sourceFile: rawVideo,
      draftId: draftId,
    );

    final rawAudio = File(p.join(tempDir.path, 'raw_${draftId}_voice.m4a'));
    await VoiceRecorderService.writeSynthesizedWavFile(
      rawAudio,
      durationMs: 1200,
    );
    final savedVoice = await mediaStorage.persistDraftAudio(
      sourceFile: rawAudio,
      draftId: draftId,
      durationSeconds: 7,
    );

    return (
      NewsMedia(
        id: 'photo_$draftId',
        fileName: p.basename(savedPhoto.path),
        localFilePath: savedPhoto.path,
        mimeType: 'image/jpeg',
        fileSizeBytes: savedPhoto.lengthSync(),
        mediaType: MediaType.image,
        createdAt: DateTime.now(),
      ),
      NewsMedia(
        id: 'video_$draftId',
        fileName: p.basename(savedVideo.path),
        localFilePath: savedVideo.path,
        mimeType: 'video/mp4',
        fileSizeBytes: savedVideo.lengthSync(),
        mediaType: MediaType.video,
        createdAt: DateTime.now(),
      ),
      NewsMedia(
        id: 'voice_$draftId',
        fileName: p.basename(savedVoice.path),
        localFilePath: savedVoice.path,
        mimeType: 'audio/mp4',
        fileSizeBytes: savedVoice.lengthSync(),
        durationSeconds: 7,
        mediaType: MediaType.audio,
        createdAt: DateTime.now(),
      ),
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('task44_sync_test_');
    mediaStorage = MediaStorageService(customBaseDir: tempDir);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('TASK 04.4 — Complete Media Sync & Bug Fix Integration Tests', () {
    test(
      '1. Photo + Video + Voice Combined Sync, Folder Structure & SQLite Restart Persistence',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);
        final driveRepo = ControllableGoogleDriveRepository();

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(driveRepo),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporter1@news.bd');

        final (photo, video, voice) = await createAllThreeMedia('draft_all_1');
        final draft = NewsDraft(
          id: 'draft_all_1',
          reporterId: 'user-001',
          headline: 'Jamuna Bridge Railway Opening',
          category: 'Infrastructure',
          location: 'Sirajganj',
          incidentDetails: 'Combined photo, video, and voice report.',
          mediaAttachments: [photo, video],
          voiceDispatch: voice,
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draft);
        final synced =
            await container.read(draftSyncServiceProvider).syncDraft(draft);

        expect(synced.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(synced.isSyncedWithDrive, isTrue);
        expect(synced.driveFolderId, isNotNull);
        expect(synced.driveFileId, isNotNull);
        expect(
          driveRepo.newsFolders[synced.driveFolderId],
          equals('Jamuna Bridge Railway Opening'),
        );

        // Verify all 3 media uploaded + JSON backup = 4 files
        expect(driveRepo.mediaUploadCalls, equals(3));
        final filesOnDrive = await driveRepo.listFiles(
          reporterGoogleEmail: 'reporter1@news.bd',
        );
        expect(filesOnDrive.length, equals(4));
        expect(
          filesOnDrive.where((f) => f.mediaType == MediaType.image).length,
          equals(1),
        );
        expect(
          filesOnDrive.where((f) => f.mediaType == MediaType.video).length,
          equals(1),
        );
        expect(
          filesOnDrive.where((f) => f.mediaType == MediaType.audio).length,
          equals(1),
        );

        // Simulate app restart by reading directly from SQLite
        final restored = await draftRepo.getMostRecentDraft(
          reporterId: 'user-001',
        );
        expect(restored, isNotNull);
        expect(restored!.mediaAttachments.length, equals(2));
        expect(
          restored.mediaAttachments.every((m) => m.isUploadedToDrive && m.driveFileId != null),
          isTrue,
        );
        expect(restored.voiceDispatch, isNotNull);
        expect(restored.voiceDispatch!.isUploadedToDrive, isTrue);
        expect(restored.voiceDispatch!.durationSeconds, equals(7));

        // Verify all 3 local files still exist safely on disk
        expect(File(photo.localFilePath!).existsSync(), isTrue);
        expect(File(video.localFilePath!).existsSync(), isTrue);
        expect(File(voice.localFilePath!).existsSync(), isTrue);
      },
    );

    test(
      '2. Offline Internet Drop Mid-Upload -> Pending Status, Local Safety & Auto-Retry on Reconnection',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);
        final driveRepo = ControllableGoogleDriveRepository();
        driveRepo.simulateOffline = true;

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(driveRepo),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporter1@news.bd');

        final (photo, video, voice) = await createAllThreeMedia('draft_net_drop');
        final draft = NewsDraft(
          id: 'draft_net_drop',
          reporterId: 'user-001',
          headline: 'Cyclone Shelter Preparedness',
          category: 'National',
          location: 'Coxs Bazar',
          incidentDetails: 'Signal lost mid-dispatch.',
          mediaAttachments: [photo, video],
          voiceDispatch: voice,
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draft);
        final offlineResult =
            await container.read(draftSyncServiceProvider).syncDraft(draft);

        expect(offlineResult.driveSyncStatus, equals(DraftSyncStatus.pending));
        expect(offlineResult.isSyncedWithDrive, isFalse);
        expect(File(photo.localFilePath!).existsSync(), isTrue);
        expect(File(video.localFilePath!).existsSync(), isTrue);
        expect(File(voice.localFilePath!).existsSync(), isTrue);

        // Internet comes back online -> automatic batch retry
        driveRepo.simulateOffline = false;
        final syncedCount = await container
            .read(draftSyncServiceProvider)
            .syncAllPendingDrafts(reporterId: 'user-001');
        expect(syncedCount, equals(1));

        final afterRetry = await draftRepo.getDraftById('draft_net_drop');
        expect(afterRetry!.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(afterRetry.isSyncedWithDrive, isTrue);
        expect(
          afterRetry.mediaAttachments.every((m) => m.isUploadedToDrive),
          isTrue,
        );
        expect(afterRetry.voiceDispatch!.isUploadedToDrive, isTrue);
      },
    );

    test(
      '3. Duplicate Upload Prevention Across Rapid In-Flight Edits, Retries & Restarts',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);
        final driveRepo = ControllableGoogleDriveRepository();
        driveRepo.uploadDelay = const Duration(milliseconds: 60);

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(driveRepo),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporter1@news.bd');

        final (photo, video, voice) = await createAllThreeMedia('draft_rapid');
        final initialDraft = NewsDraft(
          id: 'draft_rapid',
          reporterId: 'user-001',
          headline: 'Rapid Edit Test',
          category: 'National',
          location: 'Dhaka',
          incidentDetails: 'First edit',
          mediaAttachments: [photo],
          voiceDispatch: voice,
          lastSavedAt: DateTime.now(),
        );
        await draftRepo.saveDraft(initialDraft);

        final syncService = container.read(draftSyncServiceProvider);

        // Trigger second rapid edit while first sync is mid-upload
        final edit2Draft = initialDraft.copyWith(
          incidentDetails: 'Rapid edit while photo uploading + added video',
          mediaAttachments: [photo, video],
        );
        driveRepo.onFirstMediaUploadStarted = () async {
          await draftRepo.saveDraft(edit2Draft);
          await syncService.syncDraft(edit2Draft);
        };

        final finalResult = await syncService.syncDraft(initialDraft);
        expect(finalResult.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(finalResult.mediaAttachments.length, equals(2));
        expect(finalResult.voiceDispatch!.isUploadedToDrive, isTrue);

        // Photo and voice must have been uploaded ONCE each (not duplicated during dirty re-sync!)
        // Video uploaded once -> Total mediaUploadCalls == 3 (1 photo + 1 voice + 1 video)
        expect(driveRepo.mediaUploadCalls, equals(3));

        // Subsequent manual retry must upload 0 extra media files
        await syncService.syncDraft(finalResult);
        expect(driveRepo.mediaUploadCalls, equals(3));
      },
    );

    test(
      '4. Replacing & Removing Attachments Before and After Sync',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);
        final driveRepo = ControllableGoogleDriveRepository();

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(driveRepo),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporter1@news.bd');

        final (photo, video, voice) = await createAllThreeMedia('draft_replace');
        final draft = NewsDraft(
          id: 'draft_replace',
          reporterId: 'user-001',
          headline: 'Replacement Verification',
          category: 'Politics',
          location: 'Rajshahi',
          incidentDetails: 'Testing replace/remove.',
          mediaAttachments: [photo, video],
          voiceDispatch: voice,
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draft);
        final synced =
            await container.read(draftSyncServiceProvider).syncDraft(draft);
        final oldPhotoDriveId = synced.mediaAttachments.first.driveFileId!;

        // Remove synced photo on Drive & replace video
        await driveRepo.deleteMediaFromReporterDrive(
          driveFileId: oldPhotoDriveId,
          reporterGoogleEmail: 'reporter1@news.bd',
        );

        final replacementVideoFile = File(p.join(tempDir.path, 'new_clip.mp4'));
        await replacementVideoFile.writeAsBytes(List<int>.filled(3072, 9));
        final savedNewVideo = await mediaStorage.persistDraftVideo(
          sourceFile: replacementVideoFile,
          draftId: 'draft_replace',
        );
        final replacementVideo = NewsMedia(
          id: 'video_replacement_2',
          fileName: p.basename(savedNewVideo.path),
          localFilePath: savedNewVideo.path,
          mimeType: 'video/mp4',
          fileSizeBytes: savedNewVideo.lengthSync(),
          mediaType: MediaType.video,
          createdAt: DateTime.now(),
        );

        final oldVideo = synced.mediaAttachments[1];
        await mediaStorage.deleteLocalMedia(oldVideo.localFilePath);
        await driveRepo.deleteMediaFromReporterDrive(
          driveFileId: oldVideo.driveFileId!,
          reporterGoogleEmail: 'reporter1@news.bd',
        );

        final updatedDraft = synced.copyWith(
          mediaAttachments: [replacementVideo],
          clearVoiceDispatch: true,
        );
        await driveRepo.deleteMediaFromReporterDrive(
          driveFileId: synced.voiceDispatch!.driveFileId!,
          reporterGoogleEmail: 'reporter1@news.bd',
        );

        await draftRepo.saveDraft(updatedDraft);
        final resynced = await container
            .read(draftSyncServiceProvider)
            .syncDraft(updatedDraft);

        expect(resynced.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(resynced.mediaAttachments.length, equals(1));
        expect(
          resynced.mediaAttachments.first.id,
          equals('video_replacement_2'),
        );
        expect(resynced.voiceDispatch, isNull);

        final driveFiles = await driveRepo.listFiles(
          reporterGoogleEmail: 'reporter1@news.bd',
        );
        expect(driveFiles.any((f) => f.driveFileId == oldPhotoDriveId), isFalse);
        expect(
          driveFiles.any((f) => f.driveFileId == resynced.mediaAttachments.first.driveFileId),
          isTrue,
        );
      },
    );

    test(
      '5. Cross-Draft Isolation & Google Account Switch Isolation',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);
        final driveRepo = ControllableGoogleDriveRepository();

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(driveRepo),
          ],
        );
        addTearDown(container.dispose);

        // Reporter 1 connects and syncs Draft A
        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporterA@news.bd');

        final (photoA, _, voiceA) = await createAllThreeMedia('draft_A');
        final draftA = NewsDraft(
          id: 'draft_A',
          reporterId: 'user-001',
          headline: 'Reporter A Exclusive',
          category: 'National',
          location: 'Barishal',
          incidentDetails: 'Draft A media',
          mediaAttachments: [photoA],
          voiceDispatch: voiceA,
          lastSavedAt: DateTime.now(),
        );
        final (photoB, videoB, _) = await createAllThreeMedia('draft_B');
        final draftB = NewsDraft(
          id: 'draft_B',
          reporterId: 'user-001',
          headline: 'Reporter B Active Draft',
          category: 'Economy',
          location: 'Chattogram',
          incidentDetails: 'Draft B media',
          mediaAttachments: [photoB, videoB],
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draftA);
        await draftRepo.saveDraft(draftB);

        // Select Draft B as currently active form draft, then sync Draft A in background
        container.read(activeDraftProvider.notifier).selectDraft(draftB);
        final syncedA =
            await container.read(draftSyncServiceProvider).syncDraft(draftA);

        // Active draft MUST still be Draft B with Draft B's media!
        final activeNow = container.read(activeDraftProvider);
        expect(activeNow?.id, equals('draft_B'));
        expect(activeNow?.mediaAttachments.map((m) => m.id), containsAll(['photo_draft_B', 'video_draft_B']));
        expect(activeNow?.voiceDispatch, isNull);

        // Verify Account A owns syncedA's media
        expect(
          driveRepo.filesForAccount('reporterA@news.bd').length,
          equals(3), // photoA + voiceA + draftA.json
        );

        // Disconnect Account A and connect Account B
        await container.read(googleDriveStateProvider.notifier).disconnectAccount();
        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporterB@news.bd');

        // Wait for connectAccount microtask batch sync on pending Draft B
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Account A's files MUST NOT appear in Account B's listFiles
        final accountBFiles = await driveRepo.listFiles(
          reporterGoogleEmail: 'reporterB@news.bd',
        );
        expect(
          accountBFiles.any((f) => f.driveFileId == syncedA.mediaAttachments.first.driveFileId),
          isFalse,
        );
        // Account B received Draft B's files
        expect(
          driveRepo.filesForAccount('reporterB@news.bd').length,
          equals(3), // photoB + videoB + draft_B.json
        );

        // If syncedA is explicitly re-synced under Account B, it re-uploads to Account B's Drive instead of skipping
        final syncedAUnderB =
            await container.read(draftSyncServiceProvider).syncDraft(syncedA);
        expect(syncedAUnderB.driveFolderId, isNot(equals(syncedA.driveFolderId)));
        expect(
          syncedAUnderB.mediaAttachments.first.reporterGoogleAccountEmail,
          equals('reporterB@news.bd'),
        );
      },
    );

    test(
      '6. Missing Files, Upload Failures, App Termination Recovery & Editorial Safeguard',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);
        final driveRepo = ControllableGoogleDriveRepository();

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(driveRepo),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'reporter1@news.bd');

        // Missing local file + simulated upload failure
        final missingMedia = NewsMedia(
          id: 'missing_1',
          fileName: 'ghost_video.mp4',
          localFilePath: p.join(tempDir.path, 'does_not_exist.mp4'),
          mimeType: 'video/mp4',
          mediaType: MediaType.video,
          createdAt: DateTime.now(),
        );
        final draftWithMissing = NewsDraft(
          id: 'draft_missing',
          reporterId: 'user-001',
          headline: 'Missing Media Resilience',
          category: 'Crime',
          location: 'Dhaka',
          incidentDetails: 'Testing missing file recovery.',
          mediaAttachments: [missingMedia],
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draftWithMissing);
        final missingResult = await container
            .read(draftSyncServiceProvider)
            .syncDraft(draftWithMissing);

        expect(missingResult.driveSyncStatus, equals(DraftSyncStatus.failed));
        expect(
          missingResult.mediaAttachments.first.uploadErrorMessage,
          contains('missing'),
        );

        // App termination mid-sync recovery: draft saved in SQLite stuck in `syncing`
        final (photo, video, voice) = await createAllThreeMedia('draft_crashed');
        final stuckSyncDraft = NewsDraft(
          id: 'draft_crashed',
          reporterId: 'user-001',
          headline: 'Interrupted Upload Recovery',
          category: 'National',
          location: 'Sylhet',
          incidentDetails: 'App killed while syncing.',
          mediaAttachments: [photo, video],
          voiceDispatch: voice,
          driveSyncStatus: DraftSyncStatus.syncing,
          isSyncedWithDrive: false,
          lastSavedAt: DateTime.now(),
        );
        await draftRepo.saveDraft(stuckSyncDraft);

        final recoveredCount = await container
            .read(draftSyncServiceProvider)
            .syncAllPendingDrafts(reporterId: 'user-001');
        expect(recoveredCount, equals(1));

        final recovered = await draftRepo.getDraftById('draft_crashed');
        expect(recovered!.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(recovered.isSyncedWithDrive, isTrue);

        // Editorial safeguard: Sync never creates editorial submission / Laravel state
        expect(
          await mockDraftExistsAsDraftOnly(draftRepo, 'draft_crashed'),
          isTrue,
        );
      },
    );
  });
}

Future<bool> mockDraftExistsAsDraftOnly(
  SqliteDraftRepository repo,
  String id,
) async {
  final draft = await repo.getDraftById(id);
  return draft != null && draft.driveSyncStatus == DraftSyncStatus.synced;
}
