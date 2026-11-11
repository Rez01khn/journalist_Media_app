import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/screens/news_preview_screen.dart';
import 'package:journalist_app_1/screens/submit_news_screen.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';
import 'package:journalist_app_1/services/news_validation_service.dart';
import 'package:journalist_app_1/services/voice_recorder_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MediaStorageService mediaStorage;
  late NewsValidationService validationService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('task05_preview_test_');
    mediaStorage = MediaStorageService(customBaseDir: tempDir);
    validationService = NewsValidationService();
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('TASK 05 — News Preview & Validation Tests', () {
    test(
      '1. NewsValidationService validates required headline, body, and media formats/sizes/existence',
      () async {
        // Missing headline and body + missing photo + invalid video ext + over-duration audio
        final badVideo = File(p.join(tempDir.path, 'clip.exe'));
        await badVideo.writeAsBytes([1, 2, 3, 4]);

        final validAudio = File(p.join(tempDir.path, 'voice.m4a'));
        await VoiceRecorderService.writeSynthesizedWavFile(
          validAudio,
          durationMs: 1000,
        );

        final invalidDraft = NewsDraft(
          id: 'draft_bad',
          reporterId: 'user-001',
          headline: '   ',
          category: 'National',
          location: 'Dhaka',
          incidentDetails: '',
          mediaAttachments: [
            NewsMedia(
              id: 'p_missing',
              fileName: 'missing.jpg',
              localFilePath: p.join(tempDir.path, 'does_not_exist.jpg'),
              mimeType: 'image/jpeg',
              mediaType: MediaType.image,
              createdAt: DateTime.now(),
            ),
            NewsMedia(
              id: 'v_bad',
              fileName: 'clip.exe',
              localFilePath: badVideo.path,
              mimeType: 'application/octet-stream',
              mediaType: MediaType.video,
              createdAt: DateTime.now(),
            ),
          ],
          voiceDispatch: NewsMedia(
            id: 'a_over_duration',
            fileName: 'voice.m4a',
            localFilePath: validAudio.path,
            mimeType: 'audio/mp4',
            durationSeconds: 1200, // 20 mins > 15 min max
            mediaType: MediaType.audio,
            createdAt: DateTime.now(),
          ),
          lastSavedAt: DateTime.now(),
        );

        final result =
            await validationService.validateDraft(invalidDraft, mediaStorage);
        expect(result.isValid, isFalse);
        expect(result.headlineError, equals('News headline is required.'));
        expect(
          result.bodyError,
          equals('News body / incident details are required.'),
        );
        expect(result.mediaErrors.containsKey('p_missing'), isTrue);
        expect(result.mediaErrors.containsKey('v_bad'), isTrue);
        expect(result.mediaErrors.containsKey('a_over_duration'), isTrue);

        // Now test valid complete draft with photo, video, and voice
        final validPhoto = File(p.join(tempDir.path, 'scene.jpg'));
        await validPhoto.writeAsBytes(List<int>.filled(512, 1));
        final validVideo = File(p.join(tempDir.path, 'scene.mp4'));
        await validVideo.writeAsBytes(List<int>.filled(1024, 2));

        final validDraft = NewsDraft(
          id: 'draft_good',
          reporterId: 'user-001',
          headline: 'Chattogram Port Throughput Surges',
          category: 'Economy',
          location: 'Chattogram',
          incidentDetails: 'Container operations set a new monthly record.',
          mediaAttachments: [
            NewsMedia(
              id: 'p1',
              fileName: 'scene.jpg',
              localFilePath: validPhoto.path,
              mimeType: 'image/jpeg',
              fileSizeBytes: 512,
              mediaType: MediaType.image,
              createdAt: DateTime.now(),
            ),
            NewsMedia(
              id: 'v1',
              fileName: 'scene.mp4',
              localFilePath: validVideo.path,
              mimeType: 'video/mp4',
              fileSizeBytes: 1024,
              mediaType: MediaType.video,
              createdAt: DateTime.now(),
            ),
          ],
          voiceDispatch: NewsMedia(
            id: 'a1',
            fileName: 'voice.m4a',
            localFilePath: validAudio.path,
            mimeType: 'audio/mp4',
            fileSizeBytes: validAudio.lengthSync(),
            durationSeconds: 15,
            mediaType: MediaType.audio,
            createdAt: DateTime.now(),
          ),
          lastSavedAt: DateTime.now(),
        );

        final validResult =
            await validationService.validateDraft(validDraft, mediaStorage);
        expect(validResult.isValid, isTrue);
        expect(validResult.allErrors, isEmpty);
      },
    );

    testWidgets(
      '2. SubmitNewsScreen highlights invalid fields & navigates to NewsPreviewScreen when valid',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockDraftRepo = MockDraftRepository()..clear();
        final mockDriveRepo = MockGoogleDriveRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              draftRepositoryProvider.overrideWithValue(mockDraftRepo),
              googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
              mediaStorageServiceProvider.overrideWithValue(mediaStorage),
            ],
            child: const MaterialApp(
              home: SubmitNewsScreen(),
            ),
          ),
        );
        await tester.pump();

        // Tap Preview News with empty headline and body -> validation must block & show errors
        final previewBtn = find.text('Preview News');
        await tester.ensureVisible(previewBtn);
        await tester.tap(previewBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const ValueKey('validation_summary_banner')), findsOneWidget);
        expect(find.text('News headline is required.'), findsWidgets);
        expect(
          find.text('News body / incident details are required.'),
          findsWidgets,
        );
        expect(find.byType(NewsPreviewScreen), findsNothing);

        // Fill required fields now
        await tester.ensureVisible(find.byType(TextFormField).at(0));
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Padma Rail Link Full Operations Begin',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'Mawa, Munshiganj',
        );
        await tester.enterText(
          find.byType(TextFormField).at(2),
          'Passenger and freight trains are running across the full corridor today.',
        );
        await tester.pump();

        // Tap Preview News again -> opens NewsPreviewScreen
        await tester.ensureVisible(previewBtn);
        await tester.tap(previewBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(NewsPreviewScreen), findsOneWidget);
        expect(
          find.text('Padma Rail Link Full Operations Begin'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Passenger and freight trains are running across the full corridor today.',
          ),
          findsOneWidget,
        );
        expect(find.text('Story Validated & Ready for Review'), findsOneWidget);
      },
    );

    testWidgets(
      '3. NewsPreviewScreen renders reporter details, photo/video/voice media, Edit News, and disabled Confirm Submission dialog',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final validPngBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final photoFile = File(p.join(tempDir.path, 'preview_photo.png'));
        photoFile.writeAsBytesSync(validPngBytes);
        final videoFile = File(p.join(tempDir.path, 'preview_video.mp4'));
        videoFile.writeAsBytesSync(List<int>.filled(1024, 8));
        final audioFile = File(p.join(tempDir.path, 'preview_voice.m4a'));
        await tester.runAsync(() async {
          await VoiceRecorderService.writeSynthesizedWavFile(
            audioFile,
            durationMs: 1200,
          );
        });

        final completeDraft = NewsDraft(
          id: 'draft_preview_complete',
          reporterId: 'user-001',
          headline: 'Dhaka Metro Evening Service Extended',
          category: 'National',
          location: 'Motijheel, Dhaka',
          incidentDetails: 'Extended rush-hour service begins this evening.',
          mediaAttachments: [
            NewsMedia(
              id: 'p_prev',
              fileName: 'preview_photo.png',
              localFilePath: photoFile.path,
              mimeType: 'image/png',
              fileSizeBytes: validPngBytes.length,
              mediaType: MediaType.image,
              isUploadedToDrive: true,
              driveFileId: 'drive_p_1',
              createdAt: DateTime.now(),
            ),
            NewsMedia(
              id: 'v_prev',
              fileName: 'preview_video.mp4',
              localFilePath: videoFile.path,
              mimeType: 'video/mp4',
              fileSizeBytes: 1024,
              mediaType: MediaType.video,
              isUploadedToDrive: true,
              driveFileId: 'drive_v_1',
              createdAt: DateTime.now(),
            ),
          ],
          voiceDispatch: NewsMedia(
            id: 'a_prev',
            fileName: 'preview_voice.m4a',
            localFilePath: audioFile.path,
            mimeType: 'audio/mp4',
            fileSizeBytes: audioFile.lengthSync(),
            durationSeconds: 9,
            mediaType: MediaType.audio,
            isUploadedToDrive: true,
            driveFileId: 'drive_a_1',
            createdAt: DateTime.now(),
          ),
          isSyncedWithDrive: true,
          driveSyncStatus: DraftSyncStatus.synced,
          lastSavedAt: DateTime.now(),
        );

        final validation = await tester.runAsync(
          () => validationService.validateDraft(completeDraft, mediaStorage),
        );

        final mockDraftRepo = MockDraftRepository()..clear();
        final mockDriveRepo = MockGoogleDriveRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              draftRepositoryProvider.overrideWithValue(mockDraftRepo),
              googleDriveRepositoryProvider.overrideWithValue(mockDriveRepo),
              mediaStorageServiceProvider.overrideWithValue(mediaStorage),
            ],
            child: MaterialApp(
              home: NewsPreviewScreen(
                draft: completeDraft,
                validationResult: validation,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify story + reporter + all 3 media types rendered
        expect(find.text('Dhaka Metro Evening Service Extended'), findsOneWidget);
        expect(find.text('Rezwan Karim (REP-2026-084)'), findsOneWidget);
        expect(find.text('Attached Photos (1)'), findsOneWidget);
        expect(find.text('Attached Video (1)'), findsOneWidget);
        expect(find.text('Voice Dispatch'), findsOneWidget);
        expect(
          find.text('Submission unavailable until backend integration'),
          findsOneWidget,
        );

        // Tap Confirm Submission -> Confirmation Dialog explains editorial review & backend unavailable
        await tester.tap(
          find.byKey(const ValueKey('preview_confirm_submission_btn')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Confirm Editorial Submission'), findsOneWidget);
        expect(
          find.textContaining('to an editor for editorial review'),
          findsOneWidget,
        );
        expect(
          find.text('Submission unavailable until backend integration'),
          findsNWidgets(2),
        );

        // Verify Submit to Editor action inside dialog is disabled
        final submitBtn = tester.widget<ElevatedButton>(
          find.byKey(const ValueKey('dialog_confirm_submit_disabled_btn')),
        );
        expect(submitBtn.onPressed, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}

