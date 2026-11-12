import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/models/reporter.dart';
import 'package:journalist_app_1/repositories/auth_repository.dart';
import 'package:journalist_app_1/repositories/draft_repository.dart';
export 'package:journalist_app_1/providers/auth_provider.dart';
export 'package:journalist_app_1/providers/google_drive_provider.dart';
export 'package:journalist_app_1/providers/draft_sync_provider.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';
import 'package:journalist_app_1/repositories/news_repository.dart';
import 'package:journalist_app_1/repositories/news_submission_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_draft_repository.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';
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
  return MockNewsRepository();
});

/// SQLite Database Draft Repository Provider for offline persistence
final sqliteDraftRepositoryProvider = Provider<SqliteDraftRepository>((ref) {
  return SqliteDraftRepository();
});

/// Draft repository provider defaulting to SQLite implementation
final draftRepositoryProvider = Provider<DraftRepository>((ref) {
  return ref.watch(sqliteDraftRepositoryProvider);
});


final newsSubmissionRepositoryProvider = Provider<NewsSubmissionRepository>((ref) {
  return MockNewsSubmissionRepository();
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
final activeDraftProvider =
    NotifierProvider<ActiveDraftNotifier, NewsDraft?>(ActiveDraftNotifier.new);

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
final newsListProvider =
    FutureProvider.family<List<News>, NewsStatus?>((ref, statusFilter) async {
  final newsRepo = ref.watch(newsRepositoryProvider);
  final reporter = ref.watch(currentReporterProvider).asData?.value;
  if (reporter == null) return [];
  return newsRepo.getReporterNews(
    reporterId: reporter.id,
    statusFilter: statusFilter,
  );
});

/// Aggregate submission counts provider for the dashboard
final newsStatusCountsProvider =
    FutureProvider<Map<NewsStatus, int>>((ref) async {
  final newsRepo = ref.watch(newsRepositoryProvider);
  final reporter = ref.watch(currentReporterProvider).asData?.value;
  final draftCount = ref.watch(draftCountProvider);

  if (reporter == null) {
    return {
      NewsStatus.draft: draftCount,
      NewsStatus.pending: 0,
      NewsStatus.approved: 0,
      NewsStatus.published: 0,
      NewsStatus.rejected: 0,
    };
  }

  final counts = await newsRepo.getNewsStatusCounts(reporterId: reporter.id);
  // Ensure the draft count reflects real SQLite draft storage
  counts[NewsStatus.draft] = draftCount;
  return counts;
});
