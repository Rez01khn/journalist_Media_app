import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journalist_app_1/models/auth_session.dart';
import 'package:journalist_app_1/models/auth_user.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/draft_repository.dart';
import 'package:journalist_app_1/repositories/news_submission_repository.dart';
import 'package:journalist_app_1/services/auth_api_service.dart';
import 'package:journalist_app_1/services/offline_submission_queue_service.dart';

import 'login_integration_test.dart' show InMemorySecureTokenStorage;

class _InMemoryDraftRepository implements DraftRepository {
  final Map<String, NewsDraft> _drafts = {};

  @override
  Future<void> deleteDraft(String draftId) async {
    _drafts.remove(draftId);
  }

  @override
  Future<List<NewsDraft>> getAllDrafts({required String reporterId}) async {
    return _drafts.values
        .where((d) => d.reporterId == reporterId)
        .toList();
  }

  @override
  Future<NewsDraft?> getDraftById(String draftId) async => _drafts[draftId];

  @override
  Future<List<NewsDraft>> getPendingSyncDrafts({
    required String reporterId,
  }) async {
    return getAllDrafts(reporterId: reporterId);
  }

  @override
  Future<void> saveDraft(NewsDraft draft) async {
    _drafts[draft.id] = draft;
  }
}

class _TrackingNewsSubmissionRepository implements NewsSubmissionRepository {
  final List<String> submittedDraftIds = [];

  @override
  Future<bool> exportApprovedStoryToLaravelWebsite({
    required String newsId,
  }) async {
    return false;
  }

  @override
  Future<News> previewNewsStory(NewsDraft draft) => submitNewsStory(draft);

  @override
  Future<News> submitNewsStory(NewsDraft draft) async {
    submittedDraftIds.add(draft.id);
    return News(
      id: 'news-${draft.id}',
      trackingCode: 'REP-999',
      reporterId: draft.reporterId,
      reporterName: 'Reporter',
      headline: draft.headline,
      category: draft.category,
      location: draft.location,
      incidentDetails: draft.incidentDetails,
      status: NewsStatus.pending,
      submittedAt: DateTime.now(),
    );
  }
}

AuthSession _sampleSession() {
  return AuthSession(
    accessToken: '30|jrn_offline_queue',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    abilities: const ['*'],
    user: const AuthUser(
      id: 4,
      uuid: 'uuid-4',
      userCode: 'REP-004',
      name: 'Rezwan Ahmed',
      email: 'reporter@newsdesk.local',
      role: PortalUserRole.reporter,
      designation: 'Staff Reporter',
    ),
  );
}

void main() {
  group('Offline Draft Hold & Auto-Submit Queue Tests', () {
    test('holds submitted story in Drafts when offline and auto-submits when back online', () async {
      final tokenStorage = InMemorySecureTokenStorage();
      await tokenStorage.saveSession(_sampleSession());

      final draftRepo = _InMemoryDraftRepository();
      final queueStorage = InMemoryOfflineSubmissionQueueStorage();
      final submitRepo = _TrackingNewsSubmissionRepository();

      var isOnline = false;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/session-check')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Authenticated session is active.',
              'data': _sampleSession().user.toJson(),
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(tokenStorage),
          authApiServiceProvider.overrideWithValue(
            AuthApiService(
              client: mockClient,
              baseUrlResolver: () => 'http://10.0.2.2:8000/api/v1',
            ),
          ),
          draftRepositoryProvider.overrideWithValue(draftRepo),
          offlineSubmissionQueueStorageProvider.overrideWithValue(queueStorage),
          newsSubmissionRepositoryProvider.overrideWithValue(submitRepo),
          connectivityProbeProvider.overrideWithValue(() async => isOnline),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authStateProvider.notifier).restoreSession();
      expect(container.read(authStateProvider).isAuthenticated, isTrue);

      final draft = NewsDraft(
        id: 'draft_offline_hold_1',
        reporterId: 'user-001',
        headline: 'Offline Field Report',
        category: 'Infrastructure',
        location: 'Dhaka',
        incidentDetails: 'Detailed report written offline.',
        lastSavedAt: DateTime.now(),
      );

      // 1. Submit while offline -> saved to Drafts and held in queue.
      final offlineOutcome = await container
          .read(offlineSubmissionQueueProvider.notifier)
          .submitOrHoldDraft(draft);

      expect(offlineOutcome.submitted, isFalse);
      expect(offlineOutcome.queuedOffline, isTrue);
      expect(submitRepo.submittedDraftIds, isEmpty);
      expect(await draftRepo.getDraftById(draft.id), isNotNull);
      expect(
        container.read(offlineSubmissionQueueProvider),
        contains(draft.id),
      );
      expect(await queueStorage.readQueuedDraftIds(), contains(draft.id));

      // 2. Come back online -> processPendingSubmissions auto-submits & clears draft.
      isOnline = true;
      final submittedCount = await container
          .read(offlineSubmissionQueueProvider.notifier)
          .processPendingSubmissions();

      expect(submittedCount, equals(1));
      expect(submitRepo.submittedDraftIds, equals([draft.id]));
      expect(await draftRepo.getDraftById(draft.id), isNull);
      expect(container.read(offlineSubmissionQueueProvider), isEmpty);
      expect(await queueStorage.readQueuedDraftIds(), isEmpty);
    });
  });
}
