import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/repositories/api_news_submission_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_pending_media_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_submitted_news_repository.dart';
import 'package:journalist_app_1/services/news_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeTokenStorage implements SecureTokenStorage {
  final String? token;
  const _FakeTokenStorage({this.token = '1|sanctum_valid_reporter_token'});

  @override
  Future<String?> readAccessToken() async => token;

  @override
  Future<AuthSession?> readSession() async => null;

  @override
  Future<void> saveSession(AuthSession session) async {}

  @override
  Future<void> clearSession() async {}

  @override
  Future<String> getOrCreateDeviceId() async => 'test-device-001';

  @override
  Future<void> saveLinkedGoogleDriveEmail({
    required String userKey,
    required String googleEmail,
  }) async {}

  @override
  Future<String?> readLinkedGoogleDriveEmail({required String userKey}) async => null;

  @override
  Future<void> clearLinkedGoogleDriveEmail({required String userKey}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseService dbService;
  late SqlitePendingMediaRepository pendingMediaRepo;
  late SqliteSubmittedNewsRepository submittedNewsRepo;
  late SecureTokenStorage tokenStorage;

  const validToken = '1|sanctum_valid_reporter_token';
  const reporterId = 'rep-uuid-001';

  setUp(() async {
    tokenStorage = const _FakeTokenStorage(token: validToken);

    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE submitted_news (
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

    await db.execute('''
      CREATE TABLE pending_media_registrations (
        id TEXT PRIMARY KEY,
        server_news_id TEXT NOT NULL,
        news_uuid TEXT,
        client_draft_uuid TEXT,
        media_id TEXT NOT NULL,
        drive_file_id TEXT NOT NULL,
        media_type TEXT NOT NULL,
        original_filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_size_bytes INTEGER NOT NULL,
        duration_seconds INTEGER,
        attachment_role TEXT,
        display_order INTEGER,
        drive_folder_id TEXT,
        drive_web_view_link TEXT,
        drive_download_link TEXT,
        reporter_google_email TEXT,
        status TEXT NOT NULL,
        server_media_id TEXT,
        error_message TEXT,
        idempotency_key TEXT,
        created_at TEXT NOT NULL,
        last_attempted_at TEXT,
        retry_count INTEGER DEFAULT 0
      )
    ''');

    dbService = DatabaseService(db);
    pendingMediaRepo = SqlitePendingMediaRepository(dbService);
    submittedNewsRepo = SqliteSubmittedNewsRepository(dbService);
  });

  tearDown(() async {
    await db.close();
  });

  group('TASK 06.14 — News Media Metadata API Client Unit Tests', () {
    test('registerNewsMedia sends correct payload and bearer token to POST /api/v1/news/{news}/media', () async {
      String? capturedPath;
      String? capturedAuth;
      String? capturedIdempotency;
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedPath = request.url.path;
        capturedAuth = request.headers['Authorization'];
        capturedIdempotency = request.headers['Idempotency-Key'];
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'News media metadata registered successfully.',
            'data': {
              'id': 42,
              'uuid': 'media-server-uuid-001',
              'news_id': 10,
              'drive_file_id': 'gdrive_photo_123',
              'media_type': 'image',
              'upload_status': 'synced',
            },
            'meta': {'idempotent_replay': false},
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      final result = await apiService.registerNewsMedia(
        accessToken: validToken,
        serverNewsId: '10',
        driveFileId: 'gdrive_photo_123',
        mediaType: 'image',
        originalFilename: 'field_evidence.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 2048576,
        uuid: 'a8b1c2d3-e4f5-4a6b-8c7d-9e0f1a2b3c4d',
        idempotencyKey: 'idemp-key-media-1',
        attachmentRole: 'gallery_attachment',
        displayOrder: 1,
      );

      expect(capturedPath, '/api/v1/news/10/media');
      expect(capturedAuth, 'Bearer $validToken');
      expect(capturedIdempotency, 'idemp-key-media-1');
      expect(capturedBody?['drive_file_id'], 'gdrive_photo_123');
      expect(capturedBody?['media_type'], 'image');
      expect(capturedBody?['original_filename'], 'field_evidence.jpg');
      expect(capturedBody?['file_size_bytes'], 2048576);

      expect(result.serverId, '42');
      expect(result.driveFileId, 'gdrive_photo_123');
      expect(result.isDuplicate, false);
      expect(result.idempotentReplay, false);
    });

    test('registerNewsMedia gracefully handles 409 DUPLICATE_MEDIA as duplicate match', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'DUPLICATE_MEDIA',
              'message': 'A media record with this Google Drive file ID already exists for this news story.',
              'details': {
                'existing_media_id': 99,
                'existing_media_uuid': 'existing-uuid-99',
              },
            },
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      final result = await apiService.registerNewsMedia(
        accessToken: validToken,
        serverNewsId: '10',
        driveFileId: 'gdrive_dup_file',
        mediaType: 'image',
        originalFilename: 'dup.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 1024,
      );

      expect(result.isDuplicate, true);
      expect(result.serverId, '99');
      expect(result.serverUuid, 'existing-uuid-99');
    });

    test('registerNewsMedia throws typed NewsApiException on 422 validation error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Validation failed.',
              'details': {
                'file_size_bytes': ['The file size must not exceed 25MB.'],
              },
            },
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      expect(
        () => apiService.registerNewsMedia(
          accessToken: validToken,
          serverNewsId: '10',
          driveFileId: 'huge_file',
          mediaType: 'image',
          originalFilename: 'huge.jpg',
          mimeType: 'image/jpeg',
          fileSizeBytes: 50000000,
        ),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'VALIDATION_ERROR')
              .having((e) => e.isRetryable, 'isRetryable', false)
              .having((e) => e.statusCode, 'statusCode', 422),
        ),
      );
    });
  });

  group('TASK 06.14 — End-to-End News Media Submission Flow', () {
    test('successfully registers all confirmed media and marks MediaRegistrationStatus.complete', () async {
      final registeredCalls = <String>[];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/news') {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'News submitted successfully.',
              'data': {
                'id': 101,
                'uuid': 'news-uuid-101',
                'tracking_code': 'NWS-2026-TEST1',
                'status': 'submitted',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/news/101/media') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          registeredCalls.add(body['drive_file_id'] as String);
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Media registered.',
              'data': {
                'id': registeredCalls.length + 10,
                'uuid': 'media-reg-uuid-${registeredCalls.length}',
                'news_id': 101,
                'drive_file_id': body['drive_file_id'],
                'media_type': body['media_type'],
                'upload_status': 'synced',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not found', 404);
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      final repo = ApiNewsSubmissionRepository(
        apiService: apiService,
        tokenStorage: tokenStorage,
        pendingMediaRepo: pendingMediaRepo,
        submittedNewsRepo: submittedNewsRepo,
      );

      final photo1 = NewsMedia(
        id: 'photo-1',
        fileName: 'protest1.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 102400,
        mediaType: MediaType.image,
        driveFileId: 'drive_photo_1',
        isUploadedToDrive: true, // confirmed on Drive
        createdAt: DateTime.now(),
      );

      final voice1 = NewsMedia(
        id: 'voice-1',
        fileName: 'dispatch.m4a',
        mimeType: 'audio/m4a',
        fileSizeBytes: 51200,
        durationSeconds: 120,
        mediaType: MediaType.audio,
        driveFileId: 'drive_voice_1',
        isUploadedToDrive: true, // confirmed on Drive
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'c2e8b23a-59df-4c3e-8f2e-0a5f8b9d3e1a',
        reporterId: reporterId,
        headline: 'Major Railway Bridge Inaugurated Today',
        incidentDetails: 'The new bridge connects the southern corridor with the capital city.',
        category: 'National',
        location: 'Padma, Dhaka',
        mediaAttachments: [photo1],
        voiceDispatch: voice1,
        lastSavedAt: DateTime.now(),
      );

      final submitted = await repo.submitNewsStory(draft);

      expect(submitted.id, '101');
      expect(submitted.trackingCode, 'NWS-2026-TEST1');
      expect(submitted.mediaRegistrationStatus, MediaRegistrationStatus.complete);
      expect(registeredCalls, containsAll(['drive_photo_1', 'drive_voice_1']));

      expect(submitted.mediaAttachments.first.isRegisteredOnServer, true);
      expect(submitted.voiceDispatch?.isRegisteredOnServer, true);

      // Verify no pending items left
      final pending = await pendingMediaRepo.getPendingMedia();
      expect(pending.where((p) => p.status == 'pending'), isEmpty);
    });

    test('NEVER registers media before Drive upload is confirmed and marks MediaRegistrationStatus.partial', () async {
      final registeredCalls = <String>[];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/news') {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'News submitted successfully.',
              'data': {
                'id': 102,
                'uuid': 'news-uuid-102',
                'tracking_code': 'NWS-2026-TEST2',
                'status': 'submitted',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/news/102/media') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          registeredCalls.add(body['drive_file_id'] as String);
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Media registered.',
              'data': {
                'id': 55,
                'uuid': 'media-reg-55',
                'news_id': 102,
                'drive_file_id': body['drive_file_id'],
                'media_type': body['media_type'],
                'upload_status': 'synced',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not found', 404);
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      final repo = ApiNewsSubmissionRepository(
        apiService: apiService,
        tokenStorage: tokenStorage,
        pendingMediaRepo: pendingMediaRepo,
        submittedNewsRepo: submittedNewsRepo,
      );

      // Photo 1: uploaded to Drive
      final photoConfirmed = NewsMedia(
        id: 'photo-confirmed',
        fileName: 'confirmed.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 102400,
        mediaType: MediaType.image,
        driveFileId: 'drive_confirmed_99',
        isUploadedToDrive: true,
        createdAt: DateTime.now(),
      );

      // Photo 2: NOT uploaded to Drive yet
      final photoUnconfirmed = NewsMedia(
        id: 'photo-unconfirmed',
        fileName: 'unconfirmed.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 204800,
        mediaType: MediaType.image,
        driveFileId: null, // No drive file ID!
        isUploadedToDrive: false,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'd3f9c34b-60ef-5d4f-9g3f-1b6g9c0e4f2b',
        reporterId: reporterId,
        headline: 'Storm Warnings Issued Across Coastal District',
        incidentDetails: 'Coastal authorities have advised all fishing vessels to stay close to the shore.',
        category: 'Weather',
        location: 'Cox\'s Bazar',
        mediaAttachments: [photoConfirmed, photoUnconfirmed],
        lastSavedAt: DateTime.now(),
      );

      final submitted = await repo.submitNewsStory(draft);

      expect(submitted.id, '102');
      // Only confirmed photo was registered with server!
      expect(registeredCalls, ['drive_confirmed_99']);
      expect(registeredCalls, isNot(contains('photo-unconfirmed')));

      // Requirement 9: Must NOT be marked as complete when attachments remain pending!
      expect(submitted.mediaRegistrationStatus, MediaRegistrationStatus.partial);
      expect(submitted.mediaAttachments[0].isRegisteredOnServer, true);
      expect(submitted.mediaAttachments[1].isRegisteredOnServer, false);
      expect(submitted.mediaAttachments[1].serverRegistrationStatus, 'pending');

      // Preserved in SQLite pending repository
      final pending = await pendingMediaRepo.getPendingMedia();
      expect(pending.any((p) => p.mediaId == 'photo-unconfirmed' && p.status == 'pending'), true);
    });

    test('preserves pending media on recoverable network error and retries successfully', () async {
      int mediaCallCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/news') {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'News submitted successfully.',
              'data': {
                'id': 103,
                'uuid': 'news-uuid-103',
                'tracking_code': 'NWS-2026-TEST3',
                'status': 'submitted',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/news/103/media') {
          mediaCallCount++;
          if (mediaCallCount == 1) {
            // First attempt: simulate 503 Server Error
            return http.Response(
              jsonEncode({
                'success': false,
                'error': {
                  'code': 'SERVER_ERROR',
                  'message': 'Service temporarily overloaded.',
                },
              }),
              503,
              headers: {'content-type': 'application/json'},
            );
          } else {
            // Retry attempt: succeeds
            return http.Response(
              jsonEncode({
                'success': true,
                'message': 'Registered.',
                'data': {
                  'id': 77,
                  'uuid': 'media-77',
                  'news_id': 103,
                  'drive_file_id': 'drive_retry_photo',
                  'media_type': 'image',
                  'upload_status': 'synced',
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
        }

        return http.Response('Not found', 404);
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      final repo = ApiNewsSubmissionRepository(
        apiService: apiService,
        tokenStorage: tokenStorage,
        pendingMediaRepo: pendingMediaRepo,
        submittedNewsRepo: submittedNewsRepo,
      );

      final photo = NewsMedia(
        id: 'photo-retry-test',
        fileName: 'retry_scene.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 102400,
        mediaType: MediaType.image,
        driveFileId: 'drive_retry_photo',
        isUploadedToDrive: true,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'e4a0d45c-71fa-6e5a-0a4a-2c7h0d1f5a3c',
        reporterId: reporterId,
        headline: 'Traffic Congestion Hits Central Commercial Area',
        incidentDetails: 'Major gridlocks reported along the main avenue during peak morning hours.',
        category: 'Metro',
        location: 'Motijheel, Dhaka',
        mediaAttachments: [photo],
        lastSavedAt: DateTime.now(),
      );

      // Submission succeeds, media fails with recoverable 503
      final submitted = await repo.submitNewsStory(draft);
      expect(submitted.id, '103');
      expect(submitted.mediaRegistrationStatus, MediaRegistrationStatus.pending);

      // Check SQLite pending record
      final pendingBefore = await pendingMediaRepo.getPendingMedia();
      expect(pendingBefore.length, 1);
      expect(pendingBefore.first.driveFileId, 'drive_retry_photo');
      expect(pendingBefore.first.status, 'pending');

      // Now invoke retryPendingMediaRegistrations (e.g. on reconnect)
      final retriedCount = await repo.retryPendingMediaRegistrations();
      expect(retriedCount, 1);

      // Check that pending record is now registered
      final pendingAfter = await pendingMediaRepo.getPendingMedia();
      expect(pendingAfter.isEmpty, true);

      final records = await pendingMediaRepo.getRecordsForNews('103');
      expect(records.first.status, 'registered');
      expect(records.first.serverMediaId, '77');
    });

    test('marks non-recoverable 422 error as failed and does not retry in infinite loop', () async {
      int mediaCallCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/news') {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'News submitted.',
              'data': {
                'id': 104,
                'uuid': 'news-uuid-104',
                'tracking_code': 'NWS-2026-TEST4',
                'status': 'submitted',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/news/104/media') {
          mediaCallCount++;
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'VALIDATION_ERROR',
                'message': 'File size exceeds maximum allowable limit.',
                'details': {
                  'file_size_bytes': ['The file size must not exceed 25MB.'],
                },
              },
            }),
            422,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not found', 404);
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://test-server/api/v1',
      );

      final repo = ApiNewsSubmissionRepository(
        apiService: apiService,
        tokenStorage: tokenStorage,
        pendingMediaRepo: pendingMediaRepo,
        submittedNewsRepo: submittedNewsRepo,
      );

      final oversizedPhoto = NewsMedia(
        id: 'photo-oversized',
        fileName: 'huge.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 30000000,
        mediaType: MediaType.image,
        driveFileId: 'drive_oversized_file',
        isUploadedToDrive: true,
        createdAt: DateTime.now(),
      );

      final draft = NewsDraft(
        id: 'f5b1e56d-82ab-7f6b-1b5b-3d8i1e2a6b4d',
        reporterId: reporterId,
        headline: 'Heavy Downpour Floods Major Roadways',
        incidentDetails: 'Waterlogging reported in several downtown neighborhoods following two hours of heavy rain.',
        category: 'Disaster',
        location: 'Chittagong',
        mediaAttachments: [oversizedPhoto],
        lastSavedAt: DateTime.now(),
      );

      final submitted = await repo.submitNewsStory(draft);
      expect(submitted.mediaRegistrationStatus, MediaRegistrationStatus.failed);
      expect(mediaCallCount, 1);

      // Pending table records it as 'failed' (non-recoverable)
      final allRecords = await pendingMediaRepo.getRecordsForNews('104');
      expect(allRecords.first.status, 'failed');

      // Retry should ignore permanently failed items
      final retried = await repo.retryPendingMediaRegistrations();
      expect(retried, 0);
      expect(mediaCallCount, 1); // No new call made!
    });
  });
}
