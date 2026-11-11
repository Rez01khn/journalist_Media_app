import 'package:journalist_app_1/models/news_draft.dart';

/// Abstract contract for local, offline-capable field news drafts.
///
/// Designed to interface with local SQLite / Hive / secure file cache
/// to prevent data loss when journalists work in remote field areas.
abstract class DraftRepository {
  /// Retrieves all local drafts for a given reporter.
  Future<List<NewsDraft>> getAllDrafts({required String reporterId});

  /// Retrieves a specific draft by its ID.
  Future<NewsDraft?> getDraftById(String draftId);

  /// Saves or updates a draft locally.
  Future<void> saveDraft(NewsDraft draft);

  /// Deletes a local draft.
  Future<void> deleteDraft(String draftId);

  /// Retrieves all drafts marked as pending sync or sync failed for a given reporter.
  Future<List<NewsDraft>> getPendingSyncDrafts({required String reporterId});
}

