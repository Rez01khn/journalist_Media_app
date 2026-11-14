import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/models/pending_media_registration.dart';
import 'package:journalist_app_1/repositories/news_submission_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_pending_media_repository.dart';
import 'package:journalist_app_1/repositories/sqlite/sqlite_submitted_news_repository.dart';
import 'package:journalist_app_1/services/news_api_service.dart';
import 'package:journalist_app_1/services/secure_token_storage.dart';

/// Real HTTP implementation of [NewsSubmissionRepository] that:
/// 1. Submits the news story to `POST /api/v1/news` with Sanctum token.
/// 2. For Drive-confirmed media attachments, registers their metadata
///    against the server news ID via `POST /api/v1/news/{news}/media`.
/// 3. Safely preserves pending / recoverable media registrations in SQLite
///    so they can be retried across network reconnects and app restarts.
/// 4. Ensures duplicate requests and concurrent attempts are strictly blocked.
class ApiNewsSubmissionRepository implements NewsSubmissionRepository {
  final NewsApiService _apiService;
  final SecureTokenStorage _tokenStorage;
  final SqlitePendingMediaRepository _pendingMediaRepo;
  final SqliteSubmittedNewsRepository _submittedNewsRepo;

  /// Guards against concurrent in-flight submissions for the same draft.
  final Set<String> _inFlightDrafts = {};

  /// Guards against concurrent in-flight registrations for the same media file.
  final Set<String> _inFlightMedia = {};

  ApiNewsSubmissionRepository({
    required NewsApiService apiService,
    required SecureTokenStorage tokenStorage,
    SqlitePendingMediaRepository? pendingMediaRepo,
    SqliteSubmittedNewsRepository? submittedNewsRepo,
  })  : _apiService = apiService,
        _tokenStorage = tokenStorage,
        _pendingMediaRepo = pendingMediaRepo ?? SqlitePendingMediaRepository(),
        _submittedNewsRepo = submittedNewsRepo ?? SqliteSubmittedNewsRepository();

  @override
  Future<News> submitNewsStory(NewsDraft draft) async {
    // Prevent concurrent duplicate submissions for the same draft
    if (_inFlightDrafts.contains(draft.id)) {
      throw const NewsApiException(
        code: 'DUPLICATE_IN_FLIGHT',
        message:
            'A submission for this story is already in progress. Please wait.',
      );
    }

    _inFlightDrafts.add(draft.id);
    try {
      return await _doSubmit(draft);
    } finally {
      _inFlightDrafts.remove(draft.id);
    }
  }

  Future<News> _doSubmit(NewsDraft draft) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const NewsApiException(
        code: 'UNAUTHENTICATED',
        message: 'You are not signed in. Please sign in and try again.',
      );
    }

    // The draft.id is a stable UUID (created once and persisted in SQLite).
    // We use it as both client_draft_uuid (server deduplication) and as the
    // Idempotency-Key header (safe replay on retry).
    final clientDraftUuid = _isUuid(draft.id) ? draft.id : null;

    // Build the news body from the draft's incidentDetails.
    // Falls back to aiAssistedBody if the reporter's own text is empty.
    final body = draft.incidentDetails.trim().isNotEmpty
        ? draft.incidentDetails.trim()
        : (draft.aiAssistedBody?.trim() ?? '');

    // Step 1: Submit core news text story
    final newsResult = await _apiService.submitNews(
      accessToken: token,
      headline: draft.headline,
      body: body,
      category: draft.category.trim().isNotEmpty ? draft.category : null,
      location: draft.location.trim().isNotEmpty ? draft.location : null,
      clientDraftUuid: clientDraftUuid,
      idempotencyKey: clientDraftUuid,
      driveFolderId: draft.driveFolderId,
      driveDraftJsonFileId: draft.driveFileId,
      isAiAssisted: draft.isAiAssisted,
      aiAssistedHeadline: draft.aiAssistedHeadline,
      aiAssistedBody: draft.aiAssistedBody,
    );

    // Step 2: Register media metadata against the server news ID
    final registrationOutcome = await _registerDraftMedia(
      token: token,
      serverNewsId: newsResult.serverId,
      newsUuid: newsResult.serverUuid,
      draft: draft,
    );

    // Map the server response to the Flutter News model
    return News(
      id: newsResult.serverId,
      trackingCode: newsResult.trackingCode,
      reporterId: draft.reporterId,
      reporterName: '',
      headline: draft.headline,
      category: draft.category,
      location: draft.location,
      incidentDetails: draft.incidentDetails,
      status: NewsStatus.fromString(newsResult.status),
      mediaAttachments: registrationOutcome.updatedAttachments,
      voiceDispatch: registrationOutcome.updatedVoiceDispatch,
      isAiAssisted: draft.isAiAssisted,
      mediaRegistrationStatus: registrationOutcome.status,
      submittedAt: DateTime.now(),
    );
  }

  /// Processes and registers media attachments for [draft] against [serverNewsId].
  Future<_MediaRegistrationOutcome> _registerDraftMedia({
    required String token,
    required String serverNewsId,
    required String newsUuid,
    required NewsDraft draft,
  }) async {
    final List<NewsMedia> allItems = [];
    allItems.addAll(draft.mediaAttachments);
    if (draft.voiceDispatch != null) {
      allItems.add(draft.voiceDispatch!);
    }

    if (allItems.isEmpty) {
      return _MediaRegistrationOutcome(
        status: MediaRegistrationStatus.none,
        updatedAttachments: const [],
        updatedVoiceDispatch: null,
      );
    }

    final updatedAttachments = <NewsMedia>[];
    NewsMedia? updatedVoice;
    int registeredCount = 0;
    int pendingCount = 0;
    int failedCount = 0;

    int photoIndex = 1;
    for (final media in draft.mediaAttachments) {
      final (updatedMedia, isReg, isPend) = await _processSingleMediaItem(
        token: token,
        serverNewsId: serverNewsId,
        newsUuid: newsUuid,
        clientDraftUuid: draft.id,
        media: media,
        attachmentRole: 'gallery_attachment',
        displayOrder: photoIndex++,
        driveFolderId: draft.driveFolderId,
      );
      updatedAttachments.add(updatedMedia);
      if (isReg) registeredCount++;
      if (isPend) pendingCount++;
      if (!isReg && !isPend) failedCount++;
    }

    if (draft.voiceDispatch != null) {
      final (updatedVoiceMedia, isReg, isPend) = await _processSingleMediaItem(
        token: token,
        serverNewsId: serverNewsId,
        newsUuid: newsUuid,
        clientDraftUuid: draft.id,
        media: draft.voiceDispatch!,
        attachmentRole: 'voice_dispatch',
        displayOrder: photoIndex++,
        driveFolderId: draft.driveFolderId,
      );
      updatedVoice = updatedVoiceMedia;
      if (isReg) registeredCount++;
      if (isPend) pendingCount++;
      if (!isReg && !isPend) failedCount++;
    }

    // Determine overall media registration status
    MediaRegistrationStatus overallStatus;
    if (registeredCount == allItems.length) {
      overallStatus = MediaRegistrationStatus.complete;
    } else if (registeredCount > 0) {
      overallStatus = MediaRegistrationStatus.partial;
    } else if (pendingCount > 0) {
      overallStatus = MediaRegistrationStatus.pending;
    } else if (failedCount > 0) {
      overallStatus = MediaRegistrationStatus.failed;
    } else {
      overallStatus = MediaRegistrationStatus.none;
    }

    return _MediaRegistrationOutcome(
      status: overallStatus,
      updatedAttachments: updatedAttachments,
      updatedVoiceDispatch: updatedVoice,
    );
  }

  /// Processes a single media item, checking Drive upload confirmation before API call.
  Future<(NewsMedia, bool isRegistered, bool isPending)> _processSingleMediaItem({
    required String token,
    required String serverNewsId,
    required String newsUuid,
    required String clientDraftUuid,
    required NewsMedia media,
    required String attachmentRole,
    required int displayOrder,
    String? driveFolderId,
  }) async {
    // Already registered on server previously?
    if (media.isRegisteredOnServer) {
      return (media, true, false);
    }

    // Rule 4: Never register a media item before its Drive upload is confirmed.
    final bool isDriveConfirmed = media.isUploadedToDrive &&
        media.driveFileId != null &&
        media.driveFileId!.trim().isNotEmpty;

    final mediaKey = '${serverNewsId}_${media.id}';
    final stableIdempotencyKey = _isUuid(media.id)
        ? media.id
        : 'media_${media.id}'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final effectiveIdempotencyKey = stableIdempotencyKey.length > 64
        ? stableIdempotencyKey.substring(0, 64)
        : stableIdempotencyKey;

    if (!isDriveConfirmed) {
      // Preserve as pending in SQLite for future sync once Drive upload completes
      final pendingRecord = PendingMediaRegistration(
        id: media.id,
        serverNewsId: serverNewsId,
        newsUuid: newsUuid,
        clientDraftUuid: clientDraftUuid,
        mediaId: media.id,
        driveFileId: media.driveFileId ?? '',
        mediaType: _mapMediaType(media.mediaType),
        originalFilename: media.fileName,
        mimeType: media.mimeType,
        fileSizeBytes: media.fileSizeBytes ?? 1,
        durationSeconds: media.durationSeconds,
        attachmentRole: attachmentRole,
        displayOrder: displayOrder,
        driveFolderId: driveFolderId,
        driveWebViewLink: media.driveWebViewLink,
        driveDownloadLink: media.driveDownloadLink,
        reporterGoogleEmail: media.reporterGoogleAccountEmail,
        status: 'pending',
        errorMessage: 'Drive upload pending',
        idempotencyKey: effectiveIdempotencyKey,
        createdAt: DateTime.now(),
      );
      try {
        await _pendingMediaRepo.savePendingMedia(pendingRecord);
      } catch (e) {
        debugPrint('Could not save pending media record: $e');
      }

      final updated = media.copyWith(
        isRegisteredOnServer: false,
        serverRegistrationStatus: 'pending',
        serverRegistrationError: 'Drive upload pending',
      );
      return (updated, false, true);
    }

    // Concurrent request guard
    if (_inFlightMedia.contains(mediaKey)) {
      return (media, false, true);
    }
    _inFlightMedia.add(mediaKey);

    try {
      final regResult = await _apiService.registerNewsMedia(
        accessToken: token,
        serverNewsId: serverNewsId,
        driveFileId: media.driveFileId!,
        mediaType: _mapMediaType(media.mediaType),
        originalFilename: media.fileName,
        mimeType: media.mimeType,
        fileSizeBytes: media.fileSizeBytes ?? 1,
        uuid: _isUuid(media.id) ? media.id : null,
        idempotencyKey: effectiveIdempotencyKey,
        attachmentRole: attachmentRole,
        displayOrder: displayOrder,
        durationSeconds: media.durationSeconds,
        driveFolderId: driveFolderId,
        driveWebViewLink: media.driveWebViewLink,
        driveDownloadLink: media.driveDownloadLink,
        reporterGoogleEmail: media.reporterGoogleAccountEmail,
      );

      // Registration succeeded or duplicate was gracefully resolved
      try {
        await _pendingMediaRepo.markRegistered(
          id: media.id,
          serverMediaId: regResult.serverId,
        );
      } catch (_) {}

      final updated = media.copyWith(
        isRegisteredOnServer: true,
        serverMediaId: regResult.serverId,
        serverRegistrationStatus: regResult.isDuplicate ? 'duplicate' : 'registered',
        clearServerError: true,
      );
      return (updated, true, false);
    } on NewsApiException catch (e) {
      if (e.isRetryable) {
        // Recoverable failure: save as pending in SQLite
        final pendingRecord = PendingMediaRegistration(
          id: media.id,
          serverNewsId: serverNewsId,
          newsUuid: newsUuid,
          clientDraftUuid: clientDraftUuid,
          mediaId: media.id,
          driveFileId: media.driveFileId!,
          mediaType: _mapMediaType(media.mediaType),
          originalFilename: media.fileName,
          mimeType: media.mimeType,
          fileSizeBytes: media.fileSizeBytes ?? 1,
          durationSeconds: media.durationSeconds,
          attachmentRole: attachmentRole,
          displayOrder: displayOrder,
          driveFolderId: driveFolderId,
          driveWebViewLink: media.driveWebViewLink,
          driveDownloadLink: media.driveDownloadLink,
          reporterGoogleEmail: media.reporterGoogleAccountEmail,
          status: 'pending',
          errorMessage: e.message,
          idempotencyKey: effectiveIdempotencyKey,
          createdAt: DateTime.now(),
          lastAttemptedAt: DateTime.now(),
        );
        try {
          await _pendingMediaRepo.savePendingMedia(pendingRecord);
        } catch (_) {}

        final updated = media.copyWith(
          isRegisteredOnServer: false,
          serverRegistrationStatus: 'pending',
          serverRegistrationError: e.message,
        );
        return (updated, false, true);
      }

      // Non-recoverable failure (422, 403, 404, 401)
      final pendingRecord = PendingMediaRegistration(
        id: media.id,
        serverNewsId: serverNewsId,
        newsUuid: newsUuid,
        clientDraftUuid: clientDraftUuid,
        mediaId: media.id,
        driveFileId: media.driveFileId!,
        mediaType: _mapMediaType(media.mediaType),
        originalFilename: media.fileName,
        mimeType: media.mimeType,
        fileSizeBytes: media.fileSizeBytes ?? 1,
        durationSeconds: media.durationSeconds,
        attachmentRole: attachmentRole,
        displayOrder: displayOrder,
        driveFolderId: driveFolderId,
        driveWebViewLink: media.driveWebViewLink,
        driveDownloadLink: media.driveDownloadLink,
        reporterGoogleEmail: media.reporterGoogleAccountEmail,
        status: 'failed',
        errorMessage: e.message,
        idempotencyKey: effectiveIdempotencyKey,
        createdAt: DateTime.now(),
        lastAttemptedAt: DateTime.now(),
      );
      try {
        await _pendingMediaRepo.savePendingMedia(pendingRecord);
      } catch (_) {}

      final updated = media.copyWith(
        isRegisteredOnServer: false,
        serverRegistrationStatus: 'failed',
        serverRegistrationError: e.message,
      );
      return (updated, false, false);
    } catch (e) {
      // General error: treat as recoverable pending
      final updated = media.copyWith(
        isRegisteredOnServer: false,
        serverRegistrationStatus: 'pending',
        serverRegistrationError: e.toString(),
      );
      return (updated, false, true);
    } finally {
      _inFlightMedia.remove(mediaKey);
    }
  }

  @override
  Future<int> retryPendingMediaRegistrations() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) return 0;

    final pendingList = await _pendingMediaRepo.getPendingMedia();
    if (pendingList.isEmpty) return 0;

    int successCount = 0;
    for (final record in pendingList) {
      // Must have confirmed Drive file ID
      if (record.driveFileId.isEmpty) continue;

      final mediaKey = '${record.serverNewsId}_${record.mediaId}';
      if (_inFlightMedia.contains(mediaKey)) continue;

      _inFlightMedia.add(mediaKey);
      try {
        final regResult = await _apiService.registerNewsMedia(
          accessToken: token,
          serverNewsId: record.serverNewsId,
          driveFileId: record.driveFileId,
          mediaType: record.mediaType,
          originalFilename: record.originalFilename,
          mimeType: record.mimeType,
          fileSizeBytes: record.fileSizeBytes,
          uuid: _isUuid(record.mediaId) ? record.mediaId : null,
          idempotencyKey: record.idempotencyKey,
          attachmentRole: record.attachmentRole,
          displayOrder: record.displayOrder,
          durationSeconds: record.durationSeconds,
          driveFolderId: record.driveFolderId,
          driveWebViewLink: record.driveWebViewLink,
          driveDownloadLink: record.driveDownloadLink,
          reporterGoogleEmail: record.reporterGoogleEmail,
        );

        await _pendingMediaRepo.markRegistered(
          id: record.id,
          serverMediaId: regResult.serverId,
        );
        successCount++;

        // Update submitted news record in SQLite if all its items are now registered
        await _refreshSubmittedNewsMediaStatus(record.serverNewsId);
      } on NewsApiException catch (e) {
        if (!e.isRetryable) {
          // Permanently mark failed
          await _pendingMediaRepo.markFailed(
            id: record.id,
            errorMessage: e.message,
            isPermanent: true,
          );
        } else {
          // Recoverable failure: update retry count and stop batch to avoid hammering
          await _pendingMediaRepo.markFailed(
            id: record.id,
            errorMessage: e.message,
            isPermanent: false,
          );
          break;
        }
      } catch (e) {
        await _pendingMediaRepo.markFailed(
          id: record.id,
          errorMessage: e.toString(),
          isPermanent: false,
        );
      } finally {
        _inFlightMedia.remove(mediaKey);
      }
    }

    return successCount;
  }

  Future<void> _refreshSubmittedNewsMediaStatus(String serverNewsId) async {
    try {
      final news = await _submittedNewsRepo.getSubmittedNewsById(serverNewsId);
      if (news == null) return;

      final records = await _pendingMediaRepo.getRecordsForNews(serverNewsId);
      if (records.isEmpty) {
        await _submittedNewsRepo.updateMediaRegistrationStatus(
          newsId: serverNewsId,
          status: MediaRegistrationStatus.complete,
          mediaAttachments: news.mediaAttachments,
          voiceDispatch: news.voiceDispatch,
        );
        return;
      }

      final hasPending = records.any((r) => r.status == 'pending');
      final hasFailed = records.any((r) => r.status == 'failed');
      final hasRegistered = records.any((r) => r.status == 'registered');

      MediaRegistrationStatus status;
      if (!hasPending && !hasFailed && hasRegistered) {
        status = MediaRegistrationStatus.complete;
      } else if (hasRegistered) {
        status = MediaRegistrationStatus.partial;
      } else if (hasPending) {
        status = MediaRegistrationStatus.pending;
      } else {
        status = MediaRegistrationStatus.failed;
      }

      await _submittedNewsRepo.updateMediaRegistrationStatus(
        newsId: serverNewsId,
        status: status,
        mediaAttachments: news.mediaAttachments,
        voiceDispatch: news.voiceDispatch,
      );
    } catch (e) {
      debugPrint('Could not refresh submitted news media status: $e');
    }
  }

  static String _mapMediaType(MediaType type) {
    switch (type) {
      case MediaType.audio:
        return 'audio';
      case MediaType.video:
        return 'video';
      case MediaType.image:
      case MediaType.thumbnail:
      case MediaType.document:
        return 'image';
    }
  }

  @override
  Future<News> previewNewsStory(NewsDraft draft) async {
    return News(
      id: draft.id,
      trackingCode: '',
      reporterId: draft.reporterId,
      reporterName: '',
      headline: draft.headline,
      category: draft.category,
      location: draft.location,
      incidentDetails: draft.incidentDetails,
      status: NewsStatus.draft,
      mediaAttachments: draft.mediaAttachments,
      voiceDispatch: draft.voiceDispatch,
      isAiAssisted: draft.isAiAssisted,
      mediaRegistrationStatus: MediaRegistrationStatus.none,
      submittedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> exportApprovedStoryToLaravelWebsite({
    required String newsId,
  }) async {
    return false;
  }

  static bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);
  }
}

class _MediaRegistrationOutcome {
  final MediaRegistrationStatus status;
  final List<NewsMedia> updatedAttachments;
  final NewsMedia? updatedVoiceDispatch;

  const _MediaRegistrationOutcome({
    required this.status,
    required this.updatedAttachments,
    this.updatedVoiceDispatch,
  });
}
