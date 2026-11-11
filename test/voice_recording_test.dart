import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_draft_repository.dart';
import 'package:journalist_app_1/screens/submit_news_screen.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';
import 'package:journalist_app_1/services/voice_recorder_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late MediaStorageService mediaStorage;
  late MockGoogleDriveRepository mockDriveRepo;

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
    final dbService = DatabaseService(db);
    return (db, SqliteDraftRepository(dbService));
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('task43_voice_test_');
    mediaStorage = MediaStorageService(customBaseDir: tempDir);
    mockDriveRepo = MockGoogleDriveRepository();
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('TASK 04.3 — Voice Recording Integration Tests', () {
    test(
      '1. Audio Persistence & Validation: Persists valid M4A/WAV and rejects invalid format, oversized, or over-duration files',
      () async {
        final validAudio = File(p.join(tempDir.path, 'sample_voice.m4a'));
        await VoiceRecorderService.writeSynthesizedWavFile(
          validAudio,
          durationMs: 2000,
        );

        final persisted = await mediaStorage.persistDraftAudio(
          sourceFile: validAudio,
          draftId: 'draft_voice_01',
          durationSeconds: 12,
        );

        expect(await persisted.exists(), isTrue);
        expect(p.basename(persisted.path), startsWith('voice_draft_voice_01_'));
        expect(p.extension(persisted.path), equals('.m4a'));
        expect(
          mediaStorage.resolveAudioMimeType(persisted.path),
          equals('audio/mp4'),
        );

        // Reject unsupported format
        final invalidExt = File(p.join(tempDir.path, 'notes.txt'));
        await invalidExt.writeAsString('not an audio file');
        expect(
          () => mediaStorage.persistDraftAudio(
            sourceFile: invalidExt,
            draftId: 'draft_voice_01',
          ),
          throwsA(isA<MediaValidationException>()),
        );

        // Reject oversized audio file
        expect(
          () => mediaStorage.persistDraftAudio(
            sourceFile: validAudio,
            draftId: 'draft_voice_01',
            maxSizeBytes: 100, // 100 bytes limit
          ),
          throwsA(isA<MediaValidationException>()),
        );

        // Reject audio exceeding max duration limit
        expect(
          () => mediaStorage.persistDraftAudio(
            sourceFile: validAudio,
            draftId: 'draft_voice_01',
            durationSeconds: 1200,
            maxDurationSeconds: 900,
          ),
          throwsA(isA<MediaValidationException>()),
        );
      },
    );

    test(
      '2. VoiceRecorderService Lifecycle: Supports Start, Pause, Resume, Stop, and Cancel',
      () async {
        final recorder = VoiceRecorderService();
        expect(recorder.state, equals(VoiceRecordingState.idle));

        final stagePath = p.join(tempDir.path, 'stage_rec.m4a');
        await recorder.startRecording(outputPath: stagePath);
        expect(recorder.state, equals(VoiceRecordingState.recording));

        await recorder.pauseRecording();
        expect(recorder.state, equals(VoiceRecordingState.paused));

        await recorder.resumeRecording();
        expect(recorder.state, equals(VoiceRecordingState.recording));

        final result = await recorder.stopRecording(overrideDurationSeconds: 5);
        expect(recorder.state, equals(VoiceRecordingState.idle));
        expect(result.durationSeconds, equals(5));
        expect(await File(result.filePath).exists(), isTrue);
        expect(await File(result.filePath).length(), greaterThan(44));

        // Verify cancelRecording deletes temporary file
        final cancelPath = p.join(tempDir.path, 'cancel_rec.m4a');
        await recorder.startRecording(outputPath: cancelPath);
        await File(cancelPath).writeAsBytes([1, 2, 3, 4]);
        await recorder.cancelRecording();
        expect(recorder.state, equals(VoiceRecordingState.idle));
        expect(await File(cancelPath).exists(), isFalse);
      },
    );

    test(
      '3. Automatic Google Drive Voice Upload & SQLite Restart Persistence',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'rez01khan07@gmail.com');

        final rawAudio = File(p.join(tempDir.path, 'field_voice.m4a'));
        await VoiceRecorderService.writeSynthesizedWavFile(
          rawAudio,
          durationMs: 1500,
        );
        final savedFile = await mediaStorage.persistDraftAudio(
          sourceFile: rawAudio,
          draftId: 'draft_voice_sync',
          durationSeconds: 8,
        );

        final voiceMedia = NewsMedia(
          id: 'voice_001',
          fileName: p.basename(savedFile.path),
          localFilePath: savedFile.path,
          mimeType: 'audio/mp4',
          fileSizeBytes: await savedFile.length(),
          durationSeconds: 8,
          mediaType: MediaType.audio,
          isUploadedToDrive: false,
          createdAt: DateTime.now(),
        );

        final draft = NewsDraft(
          id: 'draft_voice_sync',
          reporterId: 'user-001',
          headline: 'Sylhet Flood Relief Operations',
          category: 'National',
          location: 'Sylhet',
          incidentDetails: 'Live audio dispatch from relief camp.',
          voiceDispatch: voiceMedia,
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draft);
        final synced =
            await container.read(draftSyncServiceProvider).syncDraft(draft);

        expect(synced.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(synced.driveFolderId, isNotNull);
        expect(synced.voiceDispatch, isNotNull);
        expect(synced.voiceDispatch!.isUploadedToDrive, isTrue);
        expect(synced.voiceDispatch!.driveFileId, isNotNull);
        expect(synced.voiceDispatch!.durationSeconds, equals(8));
        expect(await savedFile.exists(), isTrue);

        // Simulate app restart by reading from SQLite
        final restored = await draftRepo.getMostRecentDraft(
          reporterId: 'user-001',
        );
        expect(restored, isNotNull);
        expect(restored!.voiceDispatch, isNotNull);
        expect(restored.voiceDispatch!.id, equals('voice_001'));
        expect(restored.voiceDispatch!.isUploadedToDrive, isTrue);
        expect(
          restored.voiceDispatch!.driveFileId,
          equals(synced.voiceDispatch!.driveFileId),
        );
        expect(restored.voiceDispatch!.durationSeconds, equals(8));
      },
    );

    test(
      '4. Offline Queue, Reconnect Auto-Retry & Duplicate Prevention',
      () async {
        final (db, draftRepo) = await createSqliteRepo();
        addTearDown(db.close);

        final container = ProviderContainer(
          overrides: [
            sqliteDraftRepositoryProvider.overrideWithValue(draftRepo),
            draftRepositoryProvider.overrideWithValue(draftRepo),
            googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
          ],
        );
        addTearDown(container.dispose);

        // Start offline (Drive disconnected)
        final rawAudio = File(p.join(tempDir.path, 'offline_voice.m4a'));
        await VoiceRecorderService.writeSynthesizedWavFile(
          rawAudio,
          durationMs: 1200,
        );
        final savedFile = await mediaStorage.persistDraftAudio(
          sourceFile: rawAudio,
          draftId: 'draft_offline_voice',
          durationSeconds: 6,
        );

        final voiceMedia = NewsMedia(
          id: 'voice_offline_1',
          fileName: p.basename(savedFile.path),
          localFilePath: savedFile.path,
          mimeType: 'audio/mp4',
          fileSizeBytes: await savedFile.length(),
          durationSeconds: 6,
          mediaType: MediaType.audio,
          isUploadedToDrive: false,
          createdAt: DateTime.now(),
        );

        final draft = NewsDraft(
          id: 'draft_offline_voice',
          reporterId: 'user-001',
          headline: 'Offline Voice Dispatch Story',
          category: 'National',
          location: 'Khulna',
          incidentDetails: 'Recorded while offline.',
          voiceDispatch: voiceMedia,
          lastSavedAt: DateTime.now(),
        );

        await draftRepo.saveDraft(draft);
        final offlineSync =
            await container.read(draftSyncServiceProvider).syncDraft(draft);

        expect(offlineSync.driveSyncStatus, equals(DraftSyncStatus.pending));
        expect(offlineSync.voiceDispatch!.isUploadedToDrive, isFalse);

        // Connect Drive -> Automatically retries pending draft & uploads audio
        await container
            .read(googleDriveStateProvider.notifier)
            .connectAccount(preferredEmail: 'rez01khan07@gmail.com');
        final count = await container
            .read(draftSyncServiceProvider)
            .syncAllPendingDrafts(reporterId: 'user-001');
        expect(count, equals(1));

        final afterReconnect =
            await draftRepo.getDraftById('draft_offline_voice');
        expect(afterReconnect, isNotNull);
        expect(afterReconnect!.driveSyncStatus, equals(DraftSyncStatus.synced));
        expect(afterReconnect.voiceDispatch!.isUploadedToDrive, isTrue);
        final firstDriveId = afterReconnect.voiceDispatch!.driveFileId;
        expect(firstDriveId, isNotNull);

        // Edit text and re-sync -> Verify voice is NOT duplicated
        final edited = afterReconnect.copyWith(
          incidentDetails: 'Updated details without changing voice recording.',
        );
        final resynced =
            await container.read(draftSyncServiceProvider).syncDraft(edited);
        expect(resynced.voiceDispatch!.driveFileId, equals(firstDriveId));

        final driveFiles = await mockDriveRepo.listFiles(
          reporterGoogleEmail: 'rez01khan07@gmail.com',
        );
        final audioFilesOnDrive =
            driveFiles.where((f) => f.mediaType == MediaType.audio).toList();
        expect(audioFilesOnDrive.length, equals(1));
      },
    );

    testWidgets(
      '5. SubmitNewsScreen Voice Recording UI Controls: Start, Pause, Resume, Stop, Playback & Delete',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockDraftRepo = MockDraftRepository();
        mockDraftRepo.clear();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              draftRepositoryProvider.overrideWithValue(mockDraftRepo),
              googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
            ],
            child: const MaterialApp(
              home: SubmitNewsScreen(),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Voice Dispatch'), findsOneWidget);
        expect(find.text('0/1 Audio'), findsOneWidget);

        // Scroll down to Voice Dispatch section
        final startBtn = find.byKey(const ValueKey('voice_start_btn'));
        await tester.ensureVisible(startBtn);
        await tester.pump();

        // 1. Start Recording
        await tester.tap(startBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('RECORDING VOICE...'), findsOneWidget);
        expect(find.text('Recording...'), findsOneWidget);

        // 2. Pause Recording
        final pauseResumeBtn =
            find.byKey(const ValueKey('voice_pause_resume_btn'));
        await tester.tap(pauseResumeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('RECORDING PAUSED'), findsOneWidget);
        expect(find.text('Paused'), findsOneWidget);

        // 3. Resume Recording
        await tester.tap(pauseResumeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('RECORDING VOICE...'), findsOneWidget);

        // 4. Stop & Save Recording
        final stopBtn = find.byKey(const ValueKey('voice_stop_btn'));
        await tester.tap(stopBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('1/1 Audio'), findsOneWidget);
        expect(find.text('Re-record'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice_play_pause_btn')),
          findsOneWidget,
        );

        // 5. Playback toggle
        await tester.tap(find.byKey(const ValueKey('voice_play_pause_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // Pause playback
        await tester.tap(find.byKey(const ValueKey('voice_play_pause_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 6. Delete recording
        await tester.tap(find.byKey(const ValueKey('voice_delete_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('0/1 Audio'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice_play_pause_btn')),
          findsNothing,
        );
      },
    );
  });
}

