import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/core/database/database_service.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_submitted_news_repository.dart';
import 'package:journalist_app_1/screens/my_news_screen.dart';
import 'package:journalist_app_1/services/news_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Test Fakes & Helpers
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _initialState;

  _FakeAuthNotifier([AuthState? initial])
      : _initialState = initial ??
            const AuthState(
              status: AuthStatus.authenticated,
              session: AuthSession(
                accessToken: '1|sanctum_valid_reporter_token',
                user: AuthUser(
                  id: 1,
                  uuid: 'rep-uuid-001',
                  userCode: 'REP-001',
                  name: 'Rezwan',
                  email: 'rezwan@newsdesk.bd',
                  role: PortalUserRole.reporter,
                  designation: 'Correspondent',
                  status: 'active',
                  isVerified: true,
                ),
              ),
            );

  @override
  AuthState build() => _initialState;

  @override
  Future<void> restoreSession() async {}
}

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
  Future<String?> readLinkedGoogleDriveEmail({required String userKey}) async =>
      null;

  @override
  Future<void> clearLinkedGoogleDriveEmail({required String userKey}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseService dbService;
  late SqliteSubmittedNewsRepository submittedRepo;

  const validToken = '1|sanctum_valid_reporter_token';

  setUp(() async {
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

    dbService = DatabaseService(db);
    submittedRepo = SqliteSubmittedNewsRepository(dbService);
  });

  tearDown(() async {
    await db.close();
  });

  group('TASK 06.15 — Reporter My News API Client Tests', () {
    test('getReporterNews sends auth bearer token and query params to GET /api/v1/news', () async {
      String? capturedAuthHeader;
      Uri? capturedUri;

      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        capturedUri = request.url;

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'My news retrieved successfully.',
            'data': [
              {
                'id': 101,
                'uuid': 'uuid-story-101',
                'tracking_code': 'JRN-20261114-AABB',
                'reporter_id': 'rep-uuid-001',
                'headline': 'Major Waterlogging in Mirpur-10 Circle',
                'category': 'National',
                'location': 'Mirpur, Dhaka',
                'incident_details': 'Waterlogging blocked three intersections.',
                'status': 'submitted',
                'priority': 'normal',
                'is_locked_for_reporter': true,
                'media_count': 2,
                'media_registration_status': 'complete',
                'submitted_at': '2026-11-14T08:30:00.000Z',
              },
            ],
            'meta': {
              'pagination': {
                'current_page': 1,
                'last_page': 1,
                'per_page': 15,
                'total': 1,
                'has_more': false,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
      );

      final stories = await apiService.getReporterNews(
        accessToken: validToken,
        statusFilter: 'submitted',
        page: 1,
        perPage: 15,
      );

      expect(capturedAuthHeader, equals('Bearer $validToken'));
      expect(capturedUri?.path, contains('/api/v1/news'));
      expect(capturedUri?.queryParameters['status'], equals('submitted'));
      expect(capturedUri?.queryParameters['page'], equals('1'));
      expect(capturedUri?.queryParameters['per_page'], equals('15'));

      expect(stories.length, equals(1));
      final story = stories.first;
      expect(story.id, equals('101'));
      expect(story.trackingCode, equals('JRN-20261114-AABB'));
      expect(story.headline, equals('Major Waterlogging in Mirpur-10 Circle'));
      expect(story.category, equals('National'));
      expect(story.location, equals('Mirpur, Dhaka'));
      expect(story.status, equals(NewsStatus.pending)); // 'submitted' maps to NewsStatus.pending
      expect(story.mediaRegistrationStatus, equals(MediaRegistrationStatus.complete));
    });

    test('getNewsDetails retrieves single story details from GET /api/v1/news/{id}', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/api/v1/news/101'));
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'News details retrieved successfully.',
            'data': {
              'id': 101,
              'uuid': 'uuid-story-101',
              'tracking_code': 'JRN-20261114-AABB',
              'headline': 'Major Waterlogging in Mirpur-10 Circle',
              'category': 'National',
              'location': 'Mirpur, Dhaka',
              'incident_details': 'Full narrative description of the waterlogging event.',
              'status': 'submitted',
              'priority': 'normal',
              'is_locked_for_reporter': true,
              'media_count': 1,
              'media_registration_status': 'complete',
              'submitted_at': '2026-11-14T08:30:00.000Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
      );

      final story = await apiService.getNewsDetails(
        accessToken: validToken,
        newsId: '101',
      );

      expect(story, isNotNull);
      expect(story!.id, equals('101'));
      expect(story.headline, equals('Major Waterlogging in Mirpur-10 Circle'));
      expect(story.incidentDetails, equals('Full narrative description of the waterlogging event.'));
    });

    test('getNewsDetails throws 403 on cross-reporter access attempt', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'This action is unauthorized.',
            },
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
      );

      expect(
        () => apiService.getNewsDetails(
          accessToken: validToken,
          newsId: 'other-reporter-story-999',
        ),
        throwsA(
          isA<NewsApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('getNewsDetails returns null on 404 not found', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'NEWS_NOT_FOUND',
              'message': 'The specified news story was not found.',
            },
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
      );

      final result = await apiService.getNewsDetails(
        accessToken: validToken,
        newsId: 'nonexistent-id',
      );
      expect(result, isNull);
    });
  });

  group('TASK 06.15 — SQLite Persistence & Reconciliation Tests', () {
    test('saveSubmittedNews persists local record and updates on reconcile without duplicates', () async {
      // 1. Initial submission saved locally with client draft UUID
      final initialStory = News(
        id: 'client-temp-uuid-001',
        trackingCode: 'JRN-20261114-001',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Highway Crash Near Savar Bus Stand',
        category: 'National',
        location: 'Savar',
        incidentDetails: 'Bus crashed into roadside barricade.',
        status: NewsStatus.pending,
        mediaRegistrationStatus: MediaRegistrationStatus.partial,
        submittedAt: DateTime(2026, 11, 14, 9, 0),
      );

      await submittedRepo.saveSubmittedNews(
        initialStory,
        clientDraftUuid: 'draft-uuid-001',
      );

      var list = await submittedRepo.getAllSubmittedNews(reporterId: 'rep-uuid-001');
      expect(list.length, equals(1));
      expect(list.first.headline, equals('Highway Crash Near Savar Bus Stand'));

      // 2. Server reconcile: server returns same story with server ID 101, same tracking code
      final serverStory = News(
        id: '101',
        trackingCode: 'JRN-20261114-001',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Highway Crash Near Savar Bus Stand (Updated Title)',
        category: 'National',
        location: 'Savar',
        incidentDetails: 'Bus crashed into roadside barricade. Casualties reported.',
        status: NewsStatus.underReview, // Status transitioned on server!
        mediaRegistrationStatus: MediaRegistrationStatus.complete,
        submittedAt: DateTime(2026, 11, 14, 9, 0),
      );

      await submittedRepo.saveSubmittedNews(serverStory);

      // Verify NO DUPLICATE rows were created!
      list = await submittedRepo.getAllSubmittedNews(reporterId: 'rep-uuid-001');
      expect(list.length, equals(1));
      expect(list.first.headline, equals('Highway Crash Near Savar Bus Stand (Updated Title)'));
      expect(list.first.status, equals(NewsStatus.underReview));
      expect(list.first.mediaRegistrationStatus, equals(MediaRegistrationStatus.complete));
    });

    test('getReporterNews correctly filters by status', () async {
      final story1 = News(
        id: 'story-1',
        trackingCode: 'JRN-001',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Story 1',
        category: 'Economy',
        location: 'Dhaka',
        incidentDetails: 'Details 1',
        status: NewsStatus.pending,
        submittedAt: DateTime(2026, 11, 14, 8, 0),
      );

      final story2 = News(
        id: 'story-2',
        trackingCode: 'JRN-002',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Story 2',
        category: 'Sports',
        location: 'Mirpur',
        incidentDetails: 'Details 2',
        status: NewsStatus.approved,
        submittedAt: DateTime(2026, 11, 14, 9, 0),
      );

      await submittedRepo.saveSubmittedNews(story1);
      await submittedRepo.saveSubmittedNews(story2);

      final pendingOnly = await submittedRepo.getReporterNews(
        reporterId: 'rep-uuid-001',
        statusFilter: NewsStatus.pending,
      );
      expect(pendingOnly.length, equals(1));
      expect(pendingOnly.first.id, equals('story-1'));

      final approvedOnly = await submittedRepo.getReporterNews(
        reporterId: 'rep-uuid-001',
        statusFilter: NewsStatus.approved,
      );
      expect(approvedOnly.length, equals(1));
      expect(approvedOnly.first.id, equals('story-2'));

      final all = await submittedRepo.getReporterNews(reporterId: 'rep-uuid-001');
      expect(all.length, equals(2));
    });

    test('enforces cross-reporter isolation in SQLite', () async {
      final reporterAStory = News(
        id: 'story-a',
        trackingCode: 'JRN-A',
        reporterId: 'reporter-a',
        reporterName: 'Reporter A',
        headline: 'Reporter A Story',
        category: 'Politics',
        location: 'Dhaka',
        incidentDetails: 'Details A',
        status: NewsStatus.pending,
        submittedAt: DateTime(2026, 11, 14, 10, 0),
      );

      final reporterBStory = News(
        id: 'story-b',
        trackingCode: 'JRN-B',
        reporterId: 'reporter-b',
        reporterName: 'Reporter B',
        headline: 'Reporter B Story',
        category: 'Crime',
        location: 'Chittagong',
        incidentDetails: 'Details B',
        status: NewsStatus.pending,
        submittedAt: DateTime(2026, 11, 14, 10, 30),
      );

      await submittedRepo.saveSubmittedNews(reporterAStory);
      await submittedRepo.saveSubmittedNews(reporterBStory);

      final reporterAStories = await submittedRepo.getAllSubmittedNews(reporterId: 'reporter-a');
      expect(reporterAStories.length, equals(1));
      expect(reporterAStories.first.id, equals('story-a'));

      final reporterBStories = await submittedRepo.getAllSubmittedNews(reporterId: 'reporter-b');
      expect(reporterBStories.length, equals(1));
      expect(reporterBStories.first.id, equals('story-b'));
    });
  });

  group('TASK 06.15 — Riverpod Offline Sync & Reconciliation Tests', () {
    test('newsListProvider falls back to local SQLite on offline network error', () async {
      // Seed SQLite with one cached story
      final cachedStory = News(
        id: 'offline-cached-101',
        trackingCode: 'JRN-OFFLINE-01',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Offline Cached Story from Yesterday',
        category: 'National',
        location: 'Dhaka',
        incidentDetails: 'Body stored offline in SQLite.',
        status: NewsStatus.pending,
        submittedAt: DateTime(2026, 11, 13, 14, 0),
      );
      await submittedRepo.saveSubmittedNews(cachedStory);

      // Mock client that simulates device being offline
      final offlineClient = MockClient((request) async {
        throw const SocketException('No Internet access');
      });

      final offlineApiService = NewsApiService(
        client: offlineClient,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
      );

      final container = ProviderContainer(
        overrides: [
          sqliteSubmittedNewsRepositoryProvider.overrideWithValue(submittedRepo),
          newsApiServiceProvider.overrideWithValue(offlineApiService),
          secureTokenStorageProvider.overrideWithValue(const _FakeTokenStorage()),
          authStateProvider.overrideWith(() => _FakeAuthNotifier()),
        ],
      );
      addTearDown(container.dispose);

      // Watch newsListProvider — must succeed and return the local cached story!
      final result = await container.read(newsListProvider(null).future);

      expect(result.length, equals(1));
      expect(result.first.id, equals('offline-cached-101'));
      expect(result.first.headline, equals('Offline Cached Story from Yesterday'));
    });

    test('newsListProvider syncs remote stories and updates SQLite cache', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'My news retrieved successfully.',
            'data': [
              {
                'id': 202,
                'uuid': 'uuid-202',
                'tracking_code': 'JRN-20261114-SYNC',
                'reporter_id': 'rep-uuid-001',
                'headline': 'Remote Synced Headline',
                'category': 'Environment',
                'location': 'Sundarbans',
                'incident_details': 'Remote news body.',
                'status': 'under_review',
                'priority': 'normal',
                'is_locked_for_reporter': true,
                'media_count': 1,
                'media_registration_status': 'complete',
                'submitted_at': '2026-11-14T10:00:00.000Z',
              },
            ],
            'meta': {'pagination': {'total': 1}},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = NewsApiService(
        client: mockClient,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
      );

      final container = ProviderContainer(
        overrides: [
          sqliteSubmittedNewsRepositoryProvider.overrideWithValue(submittedRepo),
          newsApiServiceProvider.overrideWithValue(apiService),
          secureTokenStorageProvider.overrideWithValue(const _FakeTokenStorage()),
          authStateProvider.overrideWith(() => _FakeAuthNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(newsListProvider(null).future);

      expect(result.length, equals(1));
      expect(result.first.id, equals('202'));
      expect(result.first.status, equals(NewsStatus.underReview));

      // Verify that SQLite was automatically updated
      final localStories = await submittedRepo.getAllSubmittedNews(reporterId: 'rep-uuid-001');
      expect(localStories.length, equals(1));
      expect(localStories.first.headline, equals('Remote Synced Headline'));
    });
  });

  group('TASK 06.15 — My News Screen Widget & Read-Only Review Tests', () {
    testWidgets('MyNewsScreen renders submitted news, status badge, tracking code, and details sheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final story = News(
        id: 'story-widget-101',
        trackingCode: 'JRN-20261114-WIDG',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Metro Rail Expands Service to Motijheel',
        category: 'Infrastructure',
        location: 'Motijheel, Dhaka',
        incidentDetails: 'The passenger rush was smooth on Monday morning.',
        status: NewsStatus.pending,
        mediaRegistrationStatus: MediaRegistrationStatus.complete,
        submittedAt: DateTime(2026, 11, 14, 8, 30),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            newsListProvider(null).overrideWith((ref) => Future.value([story])),
            authStateProvider.overrideWith(_FakeAuthNotifier.new),
          ],
          child: const MaterialApp(
            home: MyNewsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Card elements
      expect(find.text('Metro Rail Expands Service to Motijheel'), findsOneWidget);
      expect(find.text('INFRASTRUCTURE'), findsOneWidget);
      expect(find.text('JRN-20261114-WIDG'), findsOneWidget);
      expect(find.text('Submitted'), findsWidgets); // Status badge
      expect(find.textContaining('Motijheel, Dhaka'), findsOneWidget);
      expect(find.textContaining('Media: complete'), findsOneWidget);

      // Tap on card to open story details sheet
      await tester.tap(find.text('Metro Rail Expands Service to Motijheel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify BottomSheet modal details
      expect(find.text('Story Content:'), findsOneWidget);
      expect(find.text('The passenger rush was smooth on Monday morning.'), findsOneWidget);

      // Verify Read-Only Constraint: Story is locked for review, NO edit button present
      expect(find.textContaining('Locked for editorial review'), findsOneWidget);
      expect(find.text('Edit & Resubmit Story'), findsNothing);
      expect(find.text('Close'), findsOneWidget);

      // Dismiss details sheet
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('MyNewsScreen displays correction feedback and Edit button when status is correctionRequested', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final correctionStory = News(
        id: 'story-correction-001',
        trackingCode: 'JRN-20261114-CORR',
        reporterId: 'rep-uuid-001',
        reporterName: 'Rezwan',
        headline: 'Gas Pipeline Leak Reported in Tejgaon',
        category: 'National',
        location: 'Tejgaon',
        incidentDetails: 'Firefighters responded to a minor pipeline leak.',
        status: NewsStatus.correctionRequested,
        editorialNotes: 'Please verify the exact gas distributor name.',
        submittedAt: DateTime(2026, 11, 14, 11, 0),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            newsListProvider(null).overrideWith((ref) => Future.value([correctionStory])),
            authStateProvider.overrideWith(_FakeAuthNotifier.new),
          ],
          child: const MaterialApp(
            home: MyNewsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Status badge shows 'Correction Requested'
      expect(find.text('Correction Requested'), findsWidgets);

      // Tap on the card
      await tester.tap(find.text('Gas Pipeline Leak Reported in Tejgaon'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify correction warning box and editorial notes
      expect(find.text('Corrections Requested by Editor'), findsOneWidget);
      expect(find.text('Please verify the exact gas distributor name.'), findsOneWidget);

      // Verify "Edit & Resubmit Story" button IS present
      expect(find.text('Edit & Resubmit Story'), findsOneWidget);
    });

    testWidgets('MyNewsScreen displays clean empty state when no submissions match filter', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            newsListProvider(null).overrideWith((ref) => Future.value([])),
            authStateProvider.overrideWith(_FakeAuthNotifier.new),
          ],
          child: const MaterialApp(
            home: MyNewsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No Submissions Found'), findsOneWidget);
      expect(find.textContaining('You have no news submissions in "All"'), findsOneWidget);
    });
  });
}
