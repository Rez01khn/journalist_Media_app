import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/core/errors/google_drive_exceptions.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/google_drive_provider.dart';
import 'package:journalist_app_1/repositories/drive/google_drive_repository_impl.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';

void main() {
  group('Google Drive Exceptions & Domain Tests', () {
    test('GoogleDriveAuthCancelledException has descriptive message', () {
      const ex = GoogleDriveAuthCancelledException();
      expect(ex.message, contains('cancelled by the user'));
    });

    test('GoogleDriveOfflineException carries connectivity warning', () {
      const ex = GoogleDriveOfflineException('No active Wi-Fi or cellular network');
      expect(ex.message, contains('cellular network'));
    });

    test('GoogleDriveUploadException throws on non-existent file', () async {
      final repo = GoogleDriveRepositoryImpl();
      expect(
        () => repo.uploadMediaToReporterDrive(
          localFilePath: 'E:/non_existent_folder/missing_image.jpg',
          mediaType: MediaType.image,
          reporterGoogleEmail: 'reporter@desk.bd',
        ),
        throwsA(isA<GoogleDriveUploadException>()),
      );
    });
  });

  group('Mock Google Drive Repository Operations', () {
    late MockGoogleDriveRepository mockDriveRepo;

    setUp(() {
      mockDriveRepo = MockGoogleDriveRepository();
    });

    test('Connect, verify authorization, and disconnect Google Drive account', () async {
      const email = 'reporter.sylhet@newsroom.bd';

      expect(await mockDriveRepo.isDriveAuthorized(reporterGoogleEmail: email), isFalse);

      final token = await mockDriveRepo.authorizeDrive(reporterGoogleEmail: email);
      expect(token, contains(email));
      expect(await mockDriveRepo.getCurrentAccountEmail(), equals(email));
      expect(await mockDriveRepo.isDriveAuthorized(reporterGoogleEmail: email), isTrue);

      await mockDriveRepo.disconnectDrive();
      expect(await mockDriveRepo.getCurrentAccountEmail(), isNull);
      expect(await mockDriveRepo.isDriveAuthorized(reporterGoogleEmail: email), isFalse);
    });

    test('App-specific folder creation returns valid ID', () async {
      const email = 'reporter@field.bd';
      final folderId = await mockDriveRepo.getOrCreateAppFolder(
        folderName: 'Journalist App Dispatches',
        reporterGoogleEmail: email,
      );
      expect(folderId, contains('Journalist App Dispatches'));
    });

    test('Upload, list, and delete media files (images, audio, drafts)', () async {
      const email = 'reporter@field.bd';

      // 1. Upload an image
      final imageMedia = await mockDriveRepo.uploadMediaToReporterDrive(
        localFilePath: '/tmp/field_photo_101.jpg',
        mediaType: MediaType.image,
        reporterGoogleEmail: email,
      );
      expect(imageMedia.isUploadedToDrive, isTrue);
      expect(imageMedia.driveFileId, isNotNull);
      expect(imageMedia.driveWebViewLink, contains('drive.google.com'));
      expect(imageMedia.mimeType, equals('image/jpeg'));

      // 2. Upload an audio dispatch
      final audioMedia = await mockDriveRepo.uploadMediaToReporterDrive(
        localFilePath: '/tmp/field_dispatch.m4a',
        mediaType: MediaType.audio,
        reporterGoogleEmail: email,
      );
      expect(audioMedia.mediaType, equals(MediaType.audio));
      expect(audioMedia.mimeType, equals('audio/mp4'));

      // 3. Upload a draft JSON backup
      final draftFile = await mockDriveRepo.uploadDraftFile(
        localFilePath: '/tmp/draft_backup_001.json',
        draftId: 'draft-001',
        reporterGoogleEmail: email,
      );
      expect(draftFile.mediaType, equals(MediaType.document));
      expect(draftFile.mimeType, equals('application/json'));

      // 4. List files
      final files = await mockDriveRepo.listFiles(reporterGoogleEmail: email);
      expect(files.length, equals(3));

      // 5. Delete file
      final deleteSuccess = await mockDriveRepo.deleteMediaFromReporterDrive(
        driveFileId: imageMedia.driveFileId!,
        reporterGoogleEmail: email,
      );
      expect(deleteSuccess, isTrue);

      final filesAfterDelete = await mockDriveRepo.listFiles(reporterGoogleEmail: email);
      expect(filesAfterDelete.length, equals(2));
      expect(filesAfterDelete.any((f) => f.driveFileId == imageMedia.driveFileId), isFalse);
    });
  });

  group('GoogleDriveNotifier Riverpod State Management', () {
    late ProviderContainer container;
    late MockGoogleDriveRepository mockRepo;

    setUp(() {
      mockRepo = MockGoogleDriveRepository();
      container = ProviderContainer(
        overrides: [
          googleDriveRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is not connected', () {
      final state = container.read(googleDriveStateProvider);
      expect(state.isConnected, isFalse);
      expect(state.accountEmail, isNull);
      expect(state.files, isEmpty);
    });

    test('connectAccount updates state and populates folder ID and files', () async {
      final notifier = container.read(googleDriveStateProvider.notifier);

      final success = await notifier.connectAccount(preferredEmail: 'field.reporter@news.bd');
      expect(success, isTrue);

      final state = container.read(googleDriveStateProvider);
      expect(state.isConnected, isTrue);
      expect(state.accountEmail, equals('field.reporter@news.bd'));
      expect(state.folderId, isNotNull);
      expect(state.errorMessage, isNull);
    });

    test('uploadMedia updates files list in state', () async {
      final notifier = container.read(googleDriveStateProvider.notifier);
      await notifier.connectAccount(preferredEmail: 'field.reporter@news.bd');

      // Create a temporary file on disk for realistic upload
      final tempDir = Directory.systemTemp.createTempSync('drive_test_');
      final tempFile = File('${tempDir.path}/test_upload_photo.jpg');
      tempFile.writeAsStringSync('fake-image-bytes');

      final uploaded = await notifier.uploadMedia(
        localFilePath: tempFile.path,
        mediaType: MediaType.image,
      );

      expect(uploaded, isNotNull);
      expect(uploaded!.isUploadedToDrive, isTrue);

      final state = container.read(googleDriveStateProvider);
      expect(state.files.length, equals(1));
      expect(state.files.first.driveFileId, equals(uploaded.driveFileId));

      // Test delete
      final deleted = await notifier.deleteMedia(uploaded.driveFileId!);
      expect(deleted, isTrue);

      final stateAfterDelete = container.read(googleDriveStateProvider);
      expect(stateAfterDelete.files, isEmpty);

      // Clean temp
      tempDir.deleteSync(recursive: true);
    });

    test('disconnectAccount resets state to initial default', () async {
      final notifier = container.read(googleDriveStateProvider.notifier);
      await notifier.connectAccount(preferredEmail: 'field.reporter@news.bd');

      await notifier.disconnectAccount();

      final state = container.read(googleDriveStateProvider);
      expect(state.isConnected, isFalse);
      expect(state.accountEmail, isNull);
      expect(state.files, isEmpty);
    });
  });
}

