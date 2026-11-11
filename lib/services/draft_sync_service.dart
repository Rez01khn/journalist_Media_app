import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/repositories/draft_repository.dart';
import 'package:journalist_app_1/repositories/google_drive_repository.dart';

/// Service managing automatic background synchronization of local SQLite drafts
/// to the reporter's personal Google Drive folder.
///
/// CRITICAL ARCHITECTURAL RULES:
/// 1. Local SQLite storage is ALWAYS written first (offline-first).
/// 2. Draft synchronization runs non-blocking in background without blocking UI or typing.
/// 3. Overlapping sync operations on the same draft are prevented.
/// 4. If draft is modified while sync is in flight, newer local changes are never overwritten.
/// 5. Google Drive sync NEVER submits news for editorial review.
class DraftSyncService {
  final Ref _ref;
  final DraftRepository _draftRepo;
  final GoogleDriveRepository _driveRepo;

  // Track active syncing drafts to prevent overlapping upload calls
  final Set<String> _activeSyncingDraftIds = {};

  // Track draft IDs that received new local edits while sync was in flight
  final Set<String> _dirtyDuringSync = {};

  // Track which Google account email owns a draft's Drive IDs in memory
  final Map<String, String> _draftSyncedOwnerEmails = {};

  static const EventChannel _connectivityChannel =
      EventChannel('com.example.journalist_app_1/connectivity');
  StreamSubscription<dynamic>? _connectivitySub;
  bool? _lastConnectivityState;

  // Prevent concurrent batch sync operations
  bool _isBatchSyncing = false;
  bool _isDisposed = false;

  DraftSyncService(this._ref, this._draftRepo, this._driveRepo) {
    _startConnectivityListener();
  }

  void _startConnectivityListener() {
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      _connectivitySub = _connectivityChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (_isDisposed) return;
          final isOnline = event == true;
          final transitionedOnline =
              _lastConnectivityState == false && isOnline;
          _lastConnectivityState = isOnline;
          if (transitionedOnline || (_lastConnectivityState == true && isOnline)) {
            Future.microtask(() {
              if (!_isDisposed) {
                syncAllPendingDrafts();
              }
            });
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Ignored in environments where native EventChannel is unavailable
    }
  }

  void dispose() {
    _isDisposed = true;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Checks if a specific draft is currently syncing to Drive.
  bool isSyncing(String draftId) => _activeSyncingDraftIds.contains(draftId);

  bool _isOfflineError(Object error) {
    final msg = error.toString().toLowerCase();
    return error is SocketException ||
        msg.contains('offline') ||
        msg.contains('failed host lookup') ||
        msg.contains('socketexception');
  }

  bool _isAccountStillActive(String expectedEmail) {
    if (_isDisposed) return false;
    final state = _ref.read(googleDriveStateProvider);
    return state.isConnected && state.accountEmail == expectedEmail;
  }

  void _updateActiveDraftIfMatching(NewsDraft updated) {
    if (_isDisposed) return;
    final active = _ref.read(activeDraftProvider);
    if (active != null && active.id == updated.id) {
      _ref.read(activeDraftProvider.notifier).selectDraft(updated);
    }
  }

  bool _belongsToDifferentAccount(NewsDraft draft, String targetEmail) {
    final recordedOwner = _draftSyncedOwnerEmails[draft.id];
    if (recordedOwner != null && recordedOwner != targetEmail) {
      return true;
    }
    for (final m in draft.mediaAttachments) {
      if (m.reporterGoogleAccountEmail != null &&
          m.reporterGoogleAccountEmail!.isNotEmpty &&
          m.reporterGoogleAccountEmail != targetEmail) {
        return true;
      }
    }
    final v = draft.voiceDispatch;
    if (v != null &&
        v.reporterGoogleAccountEmail != null &&
        v.reporterGoogleAccountEmail!.isNotEmpty &&
        v.reporterGoogleAccountEmail != targetEmail) {
      return true;
    }
    return false;
  }

  Future<(NewsMedia, bool failed, bool offline, String? error)>
      _syncSingleMedia({
    required NewsMedia media,
    required String targetEmail,
    required String newsFolderName,
    required String newsFolderId,
    required bool forceReuploadToFolder,
  }) async {
    final accountMismatch = media.reporterGoogleAccountEmail != null &&
        media.reporterGoogleAccountEmail!.isNotEmpty &&
        media.reporterGoogleAccountEmail != targetEmail;

    final needsUpload = !media.isUploadedToDrive ||
        media.driveFileId == null ||
        media.driveFileId!.isEmpty ||
        forceReuploadToFolder ||
        accountMismatch;

    if (!needsUpload) {
      return (media, false, false, null);
    }

    if (!_isAccountStillActive(targetEmail)) {
      return (
        media.copyWith(
          isUploadedToDrive: false,
          uploadErrorMessage: 'Google Drive account disconnected or switched.',
        ),
        true,
        true,
        'Google Drive account disconnected or switched.',
      );
    }

    if (media.localFilePath == null || !File(media.localFilePath!).existsSync()) {
      return (
        media.copyWith(
          isUploadedToDrive: false,
          uploadErrorMessage: 'Local media file is missing on device.',
        ),
        true,
        false,
        'Local media file missing: ${media.fileName}',
      );
    }

    try {
      final uploaded = await _driveRepo.uploadMediaToReporterDrive(
        localFilePath: media.localFilePath!,
        mediaType: media.mediaType,
        reporterGoogleEmail: targetEmail,
        targetFolderName: newsFolderName,
        targetFolderId: newsFolderId,
      );
      return (
        media.copyWith(
          driveFileId: uploaded.driveFileId,
          driveWebViewLink: uploaded.driveWebViewLink,
          driveDownloadLink: uploaded.driveDownloadLink,
          isUploadedToDrive: true,
          clearUploadError: true,
          reporterGoogleAccountEmail: targetEmail,
        ),
        false,
        false,
        null,
      );
    } catch (e) {
      return (
        media.copyWith(
          isUploadedToDrive: false,
          uploadErrorMessage: e.toString(),
        ),
        true,
        _isOfflineError(e),
        e.toString(),
      );
    }
  }

  /// Synchronizes a single draft to Google Drive.
  ///
  /// Safe to call concurrently: serializes calls per draft and automatically
  /// re-syncs if new edits occurred while the previous upload was in transit.
  Future<NewsDraft> syncDraft(NewsDraft draft) async {
    if (_isDisposed) return draft;

    // If empty draft without media or voice dispatch, do not sync
    if (draft.headline.trim().isEmpty &&
        draft.incidentDetails.trim().isEmpty &&
        draft.location.trim().isEmpty &&
        draft.mediaAttachments.isEmpty &&
        draft.voiceDispatch == null) {
      return draft;
    }

    // 1. Concurrency control: if draft is already uploading, mark dirty and return
    if (_activeSyncingDraftIds.contains(draft.id)) {
      _dirtyDuringSync.add(draft.id);
      return draft;
    }

    final driveState = _isDisposed ? null : _ref.read(googleDriveStateProvider);
    final isDriveConnected =
        driveState != null && driveState.isConnected && driveState.accountEmail != null;

    // 2. Offline / Disconnected check
    if (!isDriveConnected) {
      final pendingDraft = draft.copyWith(
        isSyncedWithDrive: false,
        driveSyncStatus: DraftSyncStatus.pending,
        syncErrorMessage: 'Google Drive is not connected.',
      );
      await _draftRepo.saveDraft(pendingDraft);
      if (!_isDisposed) {
        _updateActiveDraftIfMatching(pendingDraft);
        _ref.invalidate(draftsListProvider);
      }
      return pendingDraft;
    }

    final targetEmail = driveState.accountEmail!;
    _activeSyncingDraftIds.add(draft.id);

    // 3. Set status to syncing in SQLite and UI
    var currentDraft = draft.copyWith(
      driveSyncStatus: DraftSyncStatus.syncing,
      syncErrorMessage: null,
    );
    await _draftRepo.saveDraft(currentDraft);
    if (!_isDisposed) {
      _updateActiveDraftIfMatching(currentDraft);
      _ref.invalidate(draftsListProvider);
    }

    Directory? tempDir;
    try {
      // 4. Check account isolation: if this draft was previously synced to a
      //    different reporter's Drive account, clear old cross-account Drive IDs.
      final switchedAccount = _belongsToDifferentAccount(currentDraft, targetEmail);
      final String? existingFolderForAccount =
          switchedAccount ? null : currentDraft.driveFolderId;
      final String? existingDraftFileForAccount =
          switchedAccount ? null : currentDraft.driveFileId;

      final bool hadNewsFolderBefore = existingFolderForAccount != null &&
          existingFolderForAccount.isNotEmpty;
      final newsFolderName = currentDraft.headline.trim().isNotEmpty
          ? currentDraft.headline.trim()
          : 'Untitled News (${currentDraft.id})';

      final newsFolderId = await _driveRepo.getOrCreateNewsFolder(
        newsTitle: newsFolderName,
        reporterGoogleEmail: targetEmail,
        appFolderName: driveState.folderName,
        existingNewsFolderId: existingFolderForAccount,
      );

      if (!_isAccountStillActive(targetEmail)) {
        throw const SocketException(
          'Google Drive account disconnected or switched during sync.',
        );
      }

      if (currentDraft.driveFolderId != newsFolderId || switchedAccount) {
        currentDraft = currentDraft.copyWith(
          driveFolderId: newsFolderId,
          driveFileId: existingDraftFileForAccount,
        );
        if (!_dirtyDuringSync.contains(draft.id)) {
          await _draftRepo.saveDraft(currentDraft);
        }
      }

      // 4a. Upload any un-uploaded media attachments (photos, videos) into this News Title folder
      final updatedAttachments = <NewsMedia>[];
      bool mediaUpdated = false;
      bool anyMediaFailed = false;
      bool anyMediaOffline = false;
      String? lastMediaError;

      for (final media in currentDraft.mediaAttachments) {
        final (resMedia, failed, offline, errMsg) = await _syncSingleMedia(
          media: media,
          targetEmail: targetEmail,
          newsFolderName: newsFolderName,
          newsFolderId: newsFolderId,
          forceReuploadToFolder: !hadNewsFolderBefore,
        );
        updatedAttachments.add(resMedia);
        if (resMedia != media) mediaUpdated = true;
        if (failed) {
          anyMediaFailed = true;
          lastMediaError = errMsg;
          if (offline) anyMediaOffline = true;
        }
      }

      // 4a-ii. Upload voiceDispatch if present and not yet uploaded to this News Title folder
      NewsMedia? updatedVoiceDispatch = currentDraft.voiceDispatch;
      if (updatedVoiceDispatch != null) {
        final voice = updatedVoiceDispatch;
        final (resVoice, failed, offline, errMsg) = await _syncSingleMedia(
          media: voice,
          targetEmail: targetEmail,
          newsFolderName: newsFolderName,
          newsFolderId: newsFolderId,
          forceReuploadToFolder: !hadNewsFolderBefore,
        );
        updatedVoiceDispatch = resVoice;
        if (resVoice != voice) mediaUpdated = true;
        if (failed) {
          anyMediaFailed = true;
          lastMediaError = errMsg;
          if (offline) anyMediaOffline = true;
        }
      }

      if (mediaUpdated) {
        currentDraft = currentDraft.copyWith(
          mediaAttachments: updatedAttachments,
          voiceDispatch: updatedVoiceDispatch,
        );
        if (!_dirtyDuringSync.contains(draft.id)) {
          await _draftRepo.saveDraft(currentDraft);
          if (!_isDisposed) {
            _updateActiveDraftIfMatching(currentDraft);
            _ref.invalidate(draftsListProvider);
          }
        }
      }

      if (!_isAccountStillActive(targetEmail)) {
        throw const SocketException(
          'Google Drive account disconnected or switched during sync.',
        );
      }

      // 4b. Create stable JSON export file
      tempDir = Directory.systemTemp.createTempSync('drive_draft_${draft.id}_');
      final exportFile = File('${tempDir.path}/draft_${draft.id}.json');
      final exportPayload = {
        'id': currentDraft.id,
        'reporter_id': currentDraft.reporterId,
        'headline': currentDraft.headline,
        'category': currentDraft.category,
        'location': currentDraft.location,
        'incident_details': currentDraft.incidentDetails,
        'media_attachments':
            currentDraft.mediaAttachments.map((m) => m.toJson()).toList(),
        'voice_dispatch': currentDraft.voiceDispatch?.toJson(),
        'is_ai_assisted': currentDraft.isAiAssisted,
        'ai_assisted_headline': currentDraft.aiAssistedHeadline,
        'ai_assisted_body': currentDraft.aiAssistedBody,
        'last_saved_at': currentDraft.lastSavedAt.toIso8601String(),
        'drive_folder_id': currentDraft.driveFolderId,
        'drive_file_id': existingDraftFileForAccount,
        'synced_at': DateTime.now().toIso8601String(),
      };
      await exportFile.writeAsString(jsonEncode(exportPayload));

      // 5. Upload or update existing Google Drive backup file inside the News Title folder
      final uploaded = await _driveRepo.uploadDraftFile(
        localFilePath: exportFile.path,
        draftId: draft.id,
        reporterGoogleEmail: targetEmail,
        targetFolderName: newsFolderName,
        targetFolderId: newsFolderId,
        existingDriveFileId: existingDraftFileForAccount,
      );

      if (!_isAccountStillActive(targetEmail)) {
        throw const SocketException(
          'Google Drive account disconnected or switched during sync.',
        );
      }

      _draftSyncedOwnerEmails[draft.id] = targetEmail;

      // 6. Check if dirty edits occurred during in-flight upload
      if (_dirtyDuringSync.contains(draft.id)) {
        _dirtyDuringSync.remove(draft.id);
        _activeSyncingDraftIds.remove(draft.id);

        // Fetch latest version from SQLite and preserve newly acquired Drive IDs
        // for matching media items without resurrecting removed/replaced items.
        final latest = await _draftRepo.getDraftById(draft.id);
        if (latest != null) {
          final syncedById = {
            for (final m in currentDraft.mediaAttachments)
              if (m.isUploadedToDrive && m.driveFileId != null) m.id: m,
          };
          final mergedMedia = latest.mediaAttachments.map((m) {
            if (!m.isUploadedToDrive || m.driveFileId == null) {
              final match = syncedById[m.id];
              if (match != null) return match;
            }
            return m;
          }).toList();

          var mergedVoice = latest.voiceDispatch;
          if (mergedVoice != null &&
              (!mergedVoice.isUploadedToDrive ||
                  mergedVoice.driveFileId == null) &&
              currentDraft.voiceDispatch != null &&
              currentDraft.voiceDispatch!.id == mergedVoice.id &&
              currentDraft.voiceDispatch!.isUploadedToDrive) {
            mergedVoice = currentDraft.voiceDispatch;
          }

          final withFileId = latest.copyWith(
            mediaAttachments: mergedMedia,
            voiceDispatch: mergedVoice,
            driveFolderId: newsFolderId,
            driveFileId: uploaded.driveFileId,
          );
          await _draftRepo.saveDraft(withFileId);
          // Re-sync with the newer local edits
          return syncDraft(withFileId);
        }
      }

      // 7. Update SQLite with final sync status
      final syncedDraft = currentDraft.copyWith(
        driveFolderId: newsFolderId,
        driveFileId: uploaded.driveFileId,
        isSyncedWithDrive: !anyMediaFailed,
        driveSyncStatus: anyMediaFailed
            ? (anyMediaOffline ? DraftSyncStatus.pending : DraftSyncStatus.failed)
            : DraftSyncStatus.synced,
        lastSyncedAt: DateTime.now(),
        syncErrorMessage: anyMediaFailed ? lastMediaError : null,
      );

      await _draftRepo.saveDraft(syncedDraft);
      if (!_isDisposed) {
        _updateActiveDraftIfMatching(syncedDraft);
        _ref.invalidate(draftsListProvider);
        _ref.invalidate(draftCountProvider);
        _ref.read(googleDriveStateProvider.notifier).refreshFiles();
      }

      return syncedDraft;
    } catch (e) {
      debugPrint('Draft sync error for draft ${draft.id}: $e');
      final isOffline = _isOfflineError(e);

      final failedDraft = currentDraft.copyWith(
        isSyncedWithDrive: false,
        driveSyncStatus:
            isOffline ? DraftSyncStatus.pending : DraftSyncStatus.failed,
        syncErrorMessage: e.toString(),
      );

      await _draftRepo.saveDraft(failedDraft);
      if (!_isDisposed) {
        _updateActiveDraftIfMatching(failedDraft);
        _ref.invalidate(draftsListProvider);
      }

      return failedDraft;
    } finally {
      _activeSyncingDraftIds.remove(draft.id);
      _dirtyDuringSync.remove(draft.id);
      try {
        if (tempDir != null && tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// Automatically synchronizes all pending or failed drafts for the reporter.
  Future<int> syncAllPendingDrafts({String? reporterId}) async {
    if (_isBatchSyncing) return 0;
    _isBatchSyncing = true;

    try {
      final driveState = _ref.read(googleDriveStateProvider);
      if (!driveState.isConnected || driveState.accountEmail == null) {
        return 0;
      }

      final targetReporterId = reporterId ??
          (_ref.read(currentReporterProvider).asData?.value?.id ?? 'user-001');

      List<NewsDraft> pendingDrafts = [];
      try {
        pendingDrafts =
            await _draftRepo.getPendingSyncDrafts(reporterId: targetReporterId);
      } catch (e) {
        debugPrint('Could not retrieve pending drafts for sync: $e');
        return 0;
      }

      int syncedCount = 0;
      for (final draft in pendingDrafts) {
        final result = await syncDraft(draft);
        if (result.driveSyncStatus == DraftSyncStatus.synced) {
          syncedCount++;
        }
      }

      if (syncedCount > 0) {
        await _ref.read(googleDriveStateProvider.notifier).refreshFiles();
      }

      return syncedCount;
    } finally {
      _isBatchSyncing = false;
    }
  }
}
