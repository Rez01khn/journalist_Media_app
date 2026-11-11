import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/services/draft_sync_service.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TASK 04.2 — Video Attachment Integration Tests', () {
    late Directory tempDir;
    late MockDraftRepository mockDraftRepo;
    late MockGoogleDriveRepository mockDriveRepo;
    late ProviderContainer container;
    late DraftSyncService syncService;
    late MediaStorageService mediaStorage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('video_test_');
      mockDraftRepo = MockDraftRepository();
      mockDraftRepo.clear();
      mockDriveRepo = MockGoogleDriveRepository();
      mediaStorage = MediaStorageService();

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

    test(
        '1. Video Persistence & Validation: Persists valid MP4/MOV and rejects invalid format or oversized files',
        () async {
      // Valid MP4 video
      final validVideo = File('${tempDir.path}/field_clip.mp4');
      await validVideo.writeAsBytes(List<int>.filled(2048, 42));

      final persisted = await mediaStorage.persistDraftVideo(
        sourceFile: validVideo,
        draftId: 'draft_vid_001',
      );
      expect(persisted.existsSync(), isTrue);
      expect(persisted.path, contains('video_draft_vid_001_'));
      expect(await persisted.length(), equals(2048));
      expect(
        mediaStorage.resolveVideoMimeType(persisted.path),
        equals('video/mp4'),
      );

      // Invalid extension (.txt)
      final badFormatFile = File('${tempDir.path}/not_a_video.txt');
      await badFormatFile.writeAsString('plain text');
      expect(
        () => mediaStorage.persistDraftVideo(
          sourceFile: badFormatFile,
          draftId: 'draft_vid_001',
        ),
        throwsA(isA<MediaValidationException>()),
      );

      // Empty video (0 bytes)
      final emptyVideo = File('${tempDir.path}/empty.mp4');
      await emptyVideo.writeAsBytes(const []);
      expect(
        () => mediaStorage.persistDraftVideo(
          sourceFile: emptyVideo,
          draftId: 'draft_vid_001',
        ),
        throwsA(isA<MediaValidationException>()),
      );

      // Oversized video (exceeds custom 1 KB limit)
      expect(
        () => mediaStorage.persistDraftVideo(
          sourceFile: validVideo,
          draftId: 'draft_vid_001',
          maxSizeBytes: 1024, // 1 KB limit vs 2 KB file
        ),
        throwsA(isA<MediaValidationException>()),
      );

      // Cleanup
      await mediaStorage.deleteLocalMedia(persisted.path);
      expect(persisted.existsSync(), isFalse);
    });

    test(
        '2. Automatic Drive Video Upload: Uploads video into News Title folder and retains local file',
        () async {
      container.read(googleDriveStateProvider.notifier).state =
          const GoogleDriveState(
        isConnected: true,
        accountEmail: 'rez01khan07@gmail.com',
        folderId: 'root_folder_id',
      );

      final videoFile = File('${tempDir.path}/spot_report.mp4');
      await videoFile.writeAsBytes(List<int>.filled(4096, 7));

      final videoMedia = NewsMedia(
        id: 'video_101',
        fileName: 'spot_report.mp4',
        localFilePath: videoFile.path,
        mimeType: 'video/mp4',
        fileSizeBytes: 4096,
        mediaType: MediaType.video,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_video_sync',
        reporterId: 'user-001',
        headline: 'Highway Traffic Disruption in Gazipur',
        category: 'National',
        location: 'Gazipur',
        incidentDetails: 'Live video footage from highway.',
        mediaAttachments: [videoMedia],
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);
      final synced = await syncService.syncDraft(draft);

      expect(synced.driveSyncStatus, equals(DraftSyncStatus.synced));
      expect(synced.driveFolderId, isNotNull);
      expect(
        mockDriveRepo.newsFolders[synced.driveFolderId],
        equals('Highway Traffic Disruption in Gazipur'),
      );

      final stored = await mockDraftRepo.getDraftById('draft_video_sync');
      expect(stored, isNotNull);
      expect(stored!.mediaAttachments.length, equals(1));
      final uploadedVideo = stored.mediaAttachments.first;
      expect(uploadedVideo.mediaType, equals(MediaType.video));
      expect(uploadedVideo.isUploadedToDrive, isTrue);
      expect(uploadedVideo.driveFileId, isNotNull);
      expect(uploadedVideo.uploadErrorMessage, isNull);

      // Local video file must remain intact on device
      expect(videoFile.existsSync(), isTrue);
    });

    test(
        '3. Offline Video Attachment & Reconnect Auto-Retry: Queues offline and uploads when Drive connects',
        () async {
      container.read(googleDriveStateProvider.notifier).state =
          const GoogleDriveState(isConnected: false);

      final videoFile = File('${tempDir.path}/offline_clip.mp4');
      await videoFile.writeAsBytes(List<int>.filled(1024, 9));

      final videoMedia = NewsMedia(
        id: 'video_offline_1',
        fileName: 'offline_clip.mp4',
        localFilePath: videoFile.path,
        mimeType: 'video/mp4',
        fileSizeBytes: 1024,
        mediaType: MediaType.video,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_offline_vid',
        reporterId: 'user-001',
        headline: 'Cyclone Coastal Preparation in Coxs Bazar',
        category: 'National',
        location: 'Coxs Bazar',
        incidentDetails: 'Recorded offline during storm warning.',
        mediaAttachments: [videoMedia],
        lastSavedAt: DateTime.now(),
      );

      final pendingResult = await syncService.syncDraft(draft);
      expect(pendingResult.driveSyncStatus, equals(DraftSyncStatus.pending));
      expect(
        pendingResult.mediaAttachments.first.isUploadedToDrive,
        isFalse,
      );

      // Reconnect Google Drive
      container.read(googleDriveStateProvider.notifier).state =
          const GoogleDriveState(
        isConnected: true,
        accountEmail: 'rez01khan07@gmail.com',
        folderId: 'root_folder_id',
      );

      final syncedCount = await syncService.syncAllPendingDrafts();
      expect(syncedCount, equals(1));

      final afterReconnect =
          await mockDraftRepo.getDraftById('draft_offline_vid');
      expect(afterReconnect!.driveSyncStatus, equals(DraftSyncStatus.synced));
      expect(
        afterReconnect.mediaAttachments.first.isUploadedToDrive,
        isTrue,
      );
      expect(
        afterReconnect.mediaAttachments.first.driveFileId,
        isNotNull,
      );
    });

    test(
        '4. Duplicate Prevention & Video Replacement: Skips already synced video and uploads replaced video',
        () async {
      container.read(googleDriveStateProvider.notifier).state =
          const GoogleDriveState(
        isConnected: true,
        accountEmail: 'rez01khan07@gmail.com',
        folderId: 'root_folder_id',
      );

      final videoFile1 = File('${tempDir.path}/clip_v1.mp4');
      await videoFile1.writeAsBytes(List<int>.filled(1024, 1));

      final syncedVideo1 = NewsMedia(
        id: 'video_v1',
        fileName: 'clip_v1.mp4',
        localFilePath: videoFile1.path,
        driveFileId: 'existing_drive_video_id_1',
        mimeType: 'video/mp4',
        fileSizeBytes: 1024,
        mediaType: MediaType.video,
        isUploadedToDrive: true,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'draft_replace_vid',
        reporterId: 'user-001',
        headline: 'Port Container Operations',
        category: 'Economy',
        location: 'Chattogram',
        incidentDetails: 'First video version.',
        mediaAttachments: [syncedVideo1],
        driveFolderId: 'existing_folder_id',
        driveFileId: 'existing_draft_json_id',
        lastSavedAt: DateTime.now(),
      );

      await mockDraftRepo.saveDraft(draft);
      await syncService.syncDraft(draft);

      // Verify existing driveFileId was preserved without re-uploading
      final afterFirstSync =
          await mockDraftRepo.getDraftById('draft_replace_vid');
      expect(
        afterFirstSync!.mediaAttachments.first.driveFileId,
        equals('existing_drive_video_id_1'),
      );

      // Now replace video v1 with video v2
      final videoFile2 = File('${tempDir.path}/clip_v2.mp4');
      await videoFile2.writeAsBytes(List<int>.filled(2048, 2));
      await mediaStorage.deleteLocalMedia(videoFile1.path);
      expect(videoFile1.existsSync(), isFalse);

      final newVideo2 = NewsMedia(
        id: 'video_v2',
        fileName: 'clip_v2.mp4',
        localFilePath: videoFile2.path,
        mimeType: 'video/mp4',
        fileSizeBytes: 2048,
        mediaType: MediaType.video,
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draftWithReplacedVideo = afterFirstSync.copyWith(
        mediaAttachments: [newVideo2],
        isSyncedWithDrive: false,
        driveSyncStatus: DraftSyncStatus.pending,
      );

      await mockDraftRepo.saveDraft(draftWithReplacedVideo);
      final afterReplaceSync =
          await syncService.syncDraft(draftWithReplacedVideo);

      expect(afterReplaceSync.driveSyncStatus, equals(DraftSyncStatus.synced));
      expect(afterReplaceSync.mediaAttachments.first.id, equals('video_v2'));
      expect(afterReplaceSync.mediaAttachments.first.isUploadedToDrive, isTrue);
      expect(
        afterReplaceSync.mediaAttachments.first.driveFileId,
        isNot(equals('existing_drive_video_id_1')),
      );
    });
  });
}

