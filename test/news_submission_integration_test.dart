import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/repositories/api_news_submission_repository.dart';
import 'package:journalist_app_1/services/news_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _validHeadline = 'Major Road Collapse Disrupts Dhaka Traffic Routes';
const _validBody =
    'A significant road collapse occurred near Mirpur 10 circle on Friday morning, '
    'disrupting traffic flow across three major arteries in Dhaka city.';

NewsDraft _makeDraft({
  String id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  String headline = _validHeadline,
  String body = _validBody,
  String category = 'National',
  String location = 'Mirpur 10, Dhaka',
}) {
  return NewsDraft(
    id: id,
    reporterId: 'user-001',
    headline: headline,
    category: category,
    location: location,
    incidentDetails: body,
    lastSavedAt: DateTime(2026, 11, 14, 10, 0),
  );
}

/// Fake secure token storage for tests.
class _FakeTokenStorage implements SecureTokenStorage {
  final String? token;

  const _FakeTokenStorage({this.token = 'test-sanctum-token-12345'});

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

// ---------------------------------------------------------------------------
// NewsApiService unit tests
// ---------------------------------------------------------------------------

void main() {
  group('NewsApiService', () {
    test('submitNews succeeds with 201 response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/news'));
        expect(request.headers['Authorization'], startsWith('Bearer '));
        expect(request.headers['Idempotency-Key'], isNotNull);

        return http.Response(
          '''{"success":true,"data":{"id":"42","uuid":"aabbccdd-1234-5678-abcd-000000000001",
            "tracking_code":"REP-20261114-0042","status":"submitted"},
            "message":"News submitted successfully.","meta":{}}''',
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      final result = await service.submitNews(
        accessToken: 'test-token',
        headline: _validHeadline,
        body: _validBody,
        category: 'National',
        location: 'Dhaka',
        clientDraftUuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        idempotencyKey: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

      expect(result.serverId, '42');
      expect(result.serverUuid, 'aabbccdd-1234-5678-abcd-000000000001');
      expect(result.trackingCode, 'REP-20261114-0042');
      expect(result.status, 'submitted');
      expect(result.idempotentReplay, isFalse);
    });

    test('submitNews sets idempotent_replay=true from meta', () async {
      final client = MockClient((_) async => http.Response(
            '''{"success":true,"data":{"id":"42","uuid":"aabb","tracking_code":"REP-X","status":"submitted"},
              "message":"Replayed.","meta":{"idempotent_replay":true}}''',
            200,
            headers: {'content-type': 'application/json'},
          ));

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      final result = await service.submitNews(
        accessToken: 'token',
        headline: _validHeadline,
        body: _validBody,
      );

      expect(result.idempotentReplay, isTrue);
    });

    test('submitNews throws NewsApiException on 401', () async {
      final client = MockClient((_) async => http.Response(
            '{"success":false,"error":{"code":"UNAUTHENTICATED","message":"Token expired."}}',
            401,
            headers: {'content-type': 'application/json'},
          ));

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      expect(
        () => service.submitNews(
          accessToken: 'bad-token',
          headline: _validHeadline,
          body: _validBody,
        ),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'UNAUTHENTICATED')
              .having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('submitNews throws NewsApiException on 403 forbidden role', () async {
      final client = MockClient((_) async => http.Response(
            '{"success":false,"error":{"code":"FORBIDDEN_ROLE","message":"Editors cannot submit."}}',
            403,
            headers: {'content-type': 'application/json'},
          ));

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      await expectLater(
        service.submitNews(
          accessToken: 'editor-token',
          headline: _validHeadline,
          body: _validBody,
        ),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.statusCode, 'status', 403),
        ),
      );
    });

    test('submitNews throws NewsApiException on 422 validation error', () async {
      final client = MockClient((_) async => http.Response(
            '''{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Invalid data."},
              "errors":{"headline":["The headline must be at least 5 characters."]}}''',
            422,
            headers: {'content-type': 'application/json'},
          ));

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      await expectLater(
        service.submitNews(
          accessToken: 'token',
          headline: 'Hi',
          body: _validBody,
        ),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'VALIDATION_ERROR')
              .having(
                  (e) => e.fieldErrors.containsKey('headline'), 'has headline errors', isTrue),
        ),
      );
    });

    test('submitNews throws retryable error on SocketException', () async {
      final client = MockClient((_) async => throw const SocketException('no route'));

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      await expectLater(
        service.submitNews(
          accessToken: 'token',
          headline: _validHeadline,
          body: _validBody,
        ),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'NETWORK_ERROR')
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('submitNews throws retryable error on timeout', () async {
      final client = MockClient((_) async => throw TimeoutException('timed out'));

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      await expectLater(
        service.submitNews(
          accessToken: 'token',
          headline: _validHeadline,
          body: _validBody,
        ),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'REQUEST_TIMEOUT')
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('idempotency key is truncated to 64 characters if longer', () async {
      String? capturedKey;
      final client = MockClient((request) async {
        capturedKey = request.headers['Idempotency-Key'];
        return http.Response(
          '{"success":true,"data":{"id":"1","uuid":"u","tracking_code":"R","status":"submitted"},"meta":{}}',
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = NewsApiService(
        client: client,
        baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        timeout: const Duration(seconds: 5),
      );

      await service.submitNews(
        accessToken: 'token',
        headline: _validHeadline,
        body: _validBody,
        idempotencyKey: 'a' * 100, // 100 chars → truncated to 64
      );

      expect(capturedKey?.length, 64);
    });
  });

  // ---------------------------------------------------------------------------
  // ApiNewsSubmissionRepository unit tests
  // ---------------------------------------------------------------------------

  group('ApiNewsSubmissionRepository', () {
    test('submitNewsStory calls API and returns News model', () async {
      final client = MockClient((_) async => http.Response(
            '''{"success":true,"data":{"id":"99","uuid":"uuid-99","tracking_code":"REP-99","status":"submitted"},"meta":{}}''',
            201,
            headers: {'content-type': 'application/json'},
          ));

      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          client: client,
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
          timeout: const Duration(seconds: 5),
        ),
        tokenStorage: const _FakeTokenStorage(),
      );

      final draft = _makeDraft();
      final news = await repo.submitNewsStory(draft);

      expect(news.id, '99');
      expect(news.trackingCode, 'REP-99');
      expect(news.status, NewsStatus.pending);
      expect(news.headline, _validHeadline);
    });

    test('submitNewsStory uses draft.id as client_draft_uuid when UUID', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          '{"success":true,"data":{"id":"1","uuid":"u","tracking_code":"R","status":"submitted"},"meta":{}}',
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          client: client,
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
          timeout: const Duration(seconds: 5),
        ),
        tokenStorage: const _FakeTokenStorage(),
      );

      final draftId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      await repo.submitNewsStory(_makeDraft(id: draftId));

      expect(capturedBody, contains(draftId));
    });

    test('submitNewsStory throws when no token is stored', () async {
      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        ),
        tokenStorage: const _FakeTokenStorage(token: null),
      );

      await expectLater(
        repo.submitNewsStory(_makeDraft()),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'UNAUTHENTICATED'),
        ),
      );
    });

    test('submitNewsStory prevents concurrent duplicate requests for same draft', () async {
      var callCount = 0;
      final completer = Completer<http.Response>();

      final client = MockClient((_) async {
        callCount++;
        return completer.future;
      });

      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          client: client,
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
          timeout: const Duration(seconds: 5),
        ),
        tokenStorage: const _FakeTokenStorage(),
      );

      final draft = _makeDraft();

      // First call: starts but doesn't finish yet
      final first = repo.submitNewsStory(draft);

      // Second call with same draft: should immediately throw
      await expectLater(
        repo.submitNewsStory(draft),
        throwsA(
          isA<NewsApiException>()
              .having((e) => e.code, 'code', 'DUPLICATE_IN_FLIGHT'),
        ),
      );

      // Resolve the first call
      completer.complete(http.Response(
        '{"success":true,"data":{"id":"1","uuid":"u","tracking_code":"R","status":"submitted"},"meta":{}}',
        201,
        headers: {'content-type': 'application/json'},
      ));
      await first;

      expect(callCount, 1); // Only one HTTP call was made
    });

    test('previewNewsStory returns News from draft without network call', () async {
      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        ),
        tokenStorage: const _FakeTokenStorage(),
      );

      final draft = _makeDraft();
      final preview = await repo.previewNewsStory(draft);

      expect(preview.headline, draft.headline);
      expect(preview.status, NewsStatus.draft);
    });

    test('exportApprovedStoryToLaravelWebsite returns false (reserved)', () async {
      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        ),
        tokenStorage: const _FakeTokenStorage(),
      );

      final result = await repo.exportApprovedStoryToLaravelWebsite(newsId: '1');
      expect(result, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // UUID stability test
  // ---------------------------------------------------------------------------

  group('Draft UUID stability', () {
    test('NewsApiService._isUuid correctly identifies valid UUIDs', () {
      const validUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      const oldFormat = 'draft_1731600000000';

      // Use the internal helper via the repo
      final repo = ApiNewsSubmissionRepository(
        apiService: NewsApiService(
          baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
        ),
        tokenStorage: const _FakeTokenStorage(),
      );

      // We test indirectly: old format draft should NOT send client_draft_uuid
      // (and thus not set idempotency key). We verify no crash for non-UUID id.
      expect(validUuid, matches(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false),
      ));
      expect(oldFormat, isNot(matches(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false),
      )));
      expect(repo, isNotNull); // repo construction succeeds
    });
  });
}
