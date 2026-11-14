import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/models/reporter.dart';
import 'package:journalist_app_1/repositories/api_news_submission_repository.dart';
import 'package:journalist_app_1/repositories/auth_repository.dart';
import 'package:journalist_app_1/repositories/draft_repository.dart';
import 'package:journalist_app_1/providers/auth_provider.dart';
export 'package:journalist_app_1/providers/auth_provider.dart';
export 'package:journalist_app_1/providers/google_drive_provider.dart';
export 'package:journalist_app_1/providers/draft_sync_provider.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/repositories/news_repository.dart';
import 'package:journalist_app_1/repositories/news_submission_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_draft_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_pending_media_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_submitted_news_repository.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';
import 'package:journalist_app_1/services/news_api_service.dart';
import 'package:journalist_app_1/services/news_validation_service.dart';
import 'package:journalist_app_1/services/voice_recorder_service.dart';

final mediaStorageServiceProvider = Provider<MediaStorageService>((ref) {
  return MediaStorageService();
});

final voiceRecorderServiceProvider = Provider<VoiceRecorderService>((ref) {
  return VoiceRecorderService();
});

final newsValidationServiceProvider = Provider<NewsValidationService>((ref) {
  return NewsValidationService();
});

/// Repository Providers
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return MockAuthRepository();
});

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return ref.watch(sqliteSubmittedNewsRepositoryProvider);
});

/// SQLite Database Draft Repository Provider for offline persistence
final sqliteDraftRepositoryProvider = Provider<SqliteDraftRepository>((ref) {
  return SqliteDraftRepository();
});

final sqliteSubmittedNewsRepositoryProvider =
    Provider<SqliteSubmittedNewsRepository>((ref) {
      return SqliteSubmittedNewsRepository();
    });

final sqlitePendingMediaRepositoryProvider =
    Provider<SqlitePendingMediaRepository>((ref) {
      return SqlitePendingMediaRepository();
    });

/// Draft repository provider defaulting to SQLite implementation
final draftRepositoryProvider = Provider<DraftRepository>((ref) {
  return ref.watch(sqliteDraftRepositoryProvider);
});

final newsApiServiceProvider = Provider<NewsApiService>((ref) {
  return NewsApiService();
});

final newsSubmissionRepositoryProvider = Provider<NewsSubmissionRepository>((
  ref,
) {
  return ApiNewsSubmissionRepository(
    apiService: ref.watch(newsApiServiceProvider),
    tokenStorage: ref.watch(secureTokenStorageProvider),
    pendingMediaRepo: ref.watch(sqlitePendingMediaRepositoryProvider),
    submittedNewsRepo: ref.watch(sqliteSubmittedNewsRepositoryProvider),
  );
});

/// Current Reporter Provider
final currentReporterProvider = FutureProvider<Reporter?>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.getCurrentReporter();
});

/// Notifier managing active draft selected for editing
class ActiveDraftNotifier extends Notifier<NewsDraft?> {
  @override
  NewsDraft? build() => null;

  void selectDraft(NewsDraft? draft) {
    state = draft;
  }
}

/// Active Draft Provider (currently being edited on SubmitNewsScreen)
final activeDraftProvider = NotifierProvider<ActiveDraftNotifier, NewsDraft?>(
  ActiveDraftNotifier.new,
);

/// Drafts list provider fetching from SQLite storage
final draftsListProvider = FutureProvider<List<NewsDraft>>((ref) async {
  final draftRepo = ref.watch(draftRepositoryProvider);
  final reporter = ref.watch(currentReporterProvider).asData?.value;
  final reporterId = reporter?.id ?? 'user-001';
  return draftRepo.getAllDrafts(reporterId: reporterId);
});

/// Synchronous real-time count of saved offline drafts
final draftCountProvider = Provider<int>((ref) {
  final draftsAsync = ref.watch(draftsListProvider);
  return draftsAsync.asData?.value.length ?? 0;
});

/// News list provider with optional status filter
final newsListProvider = FutureProvider.family<List<News>, NewsStatus?>((
  ref,
  statusFilter,
) async {
  final newsRepo = ref.watch(sqliteSubmittedNewsRepositoryProvider);
  final tokenStorage = ref.watch(secureTokenStorageProvider);
  final newsApiService = ref.watch(newsApiServiceProvider);
  final authState = ref.watch(authStateProvider);
  final authUser = authState.user;
  final reporterId = authUser?.uuid ?? (authUser != null ? authUser.id.toString() : 'rep-uuid-001');

  // Attempt online sync if token is available
  try {
    final token = await tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      final remoteList = await newsApiService.getReporterNews(
        accessToken: token,
        statusFilter: statusFilter?.toValue(),
      );
      if (remoteList.isNotEmpty) {
        final withReporter = remoteList.map((n) {
          if (n.reporterId.isEmpty || n.reporterId == 'user-001') {
            return n.copyWith(reporterId: reporterId);
          }
          return n;
        }).toList();
        await newsRepo.saveAll(withReporter);
      }
    }
  } catch (_) {
    // Offline / network failure graceful fallback to SQLite
  }

  return newsRepo.getReporterNews(
    reporterId: reporterId,
    statusFilter: statusFilter,
  );
});

/// Aggregate submission counts provider for the dashboard
final newsStatusCountsProvider = FutureProvider<Map<NewsStatus, int>>((
  ref,
) async {
  final newsRepo = ref.watch(sqliteSubmittedNewsRepositoryProvider);
  final draftCount = ref.watch(draftCountProvider);
  final authState = ref.watch(authStateProvider);
  final authUser = authState.user;
  final reporterId = authUser?.uuid ?? (authUser != null ? authUser.id.toString() : 'rep-uuid-001');

  final counts = await newsRepo.getNewsStatusCounts(reporterId: reporterId);
  // Ensure the draft count reflects real SQLite draft storage
  counts[NewsStatus.draft] = draftCount;
  return counts;
});
