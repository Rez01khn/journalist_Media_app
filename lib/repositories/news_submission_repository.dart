import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';

/// Abstract contract for editorial news submission and workflow transitions.
///
/// Designed to submit finalized news stories and metadata to the independent
/// MySQL API backend, and support future editorial publication export to the
/// existing Laravel news website.
abstract class NewsSubmissionRepository {
  /// Submits a field draft for editorial review.
  ///
  /// Media files must have already been uploaded to the reporter's personal
  /// Google Drive, passing their drive file references in [draft.mediaAttachments].
  Future<News> submitNewsStory(NewsDraft draft);

  /// Generates an editorial preview of how the submitted story will look.
  Future<News> previewNewsStory(NewsDraft draft);

  /// Retries any pending media metadata registrations that previously failed
  /// due to recoverable network errors or pending Drive uploads.
  Future<int> retryPendingMediaRegistrations() async => 0;

  /// Future Phase Hook: Exports an approved story and its editorial metadata
  /// to the existing Laravel news website. Original media remains in the reporter's
  /// Google Drive and is never copied to the existing Laravel website database.
  Future<bool> exportApprovedStoryToLaravelWebsite({
    required String newsId,
  });
}

