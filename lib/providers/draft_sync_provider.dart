import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/services/draft_sync_service.dart';

/// Provider for the [DraftSyncService] engine.
final draftSyncServiceProvider = Provider<DraftSyncService>((ref) {
  final draftRepo = ref.watch(draftRepositoryProvider);
  final driveRepo = ref.watch(googleDriveRepositoryProvider);
  final service = DraftSyncService(ref, draftRepo, driveRepo);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Exposes the live sync status for the active draft being edited.
final activeDraftSyncStatusProvider = Provider<DraftSyncStatus>((ref) {
  final activeDraft = ref.watch(activeDraftProvider);
  final driveState = ref.watch(googleDriveStateProvider);

  if (activeDraft == null) return DraftSyncStatus.pending;

  if (!driveState.isConnected) {
    return DraftSyncStatus.pending;
  }

  return activeDraft.driveSyncStatus;
});
