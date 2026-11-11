import 'dart:io';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/services/media_storage_service.dart';

/// Structured result of pre-submission news validation covering required fields
/// and all attached photo, video, and voice media files.
class NewsValidationResult {
  final String? headlineError;
  final String? bodyError;
  final Map<String, String> mediaErrors;

  const NewsValidationResult({
    this.headlineError,
    this.bodyError,
    this.mediaErrors = const {},
  });

  bool get isValid =>
      headlineError == null && bodyError == null && mediaErrors.isEmpty;

  bool get hasMediaErrors => mediaErrors.isNotEmpty;

  List<String> get allErrors {
    final errors = <String>[];
    if (headlineError != null) errors.add(headlineError!);
    if (bodyError != null) errors.add(bodyError!);
    errors.addAll(mediaErrors.values);
    return errors;
  }
}

/// Validates news draft fields and attached media files against format,
/// existence, file size, and audio duration limits prior to preview/submission.
class NewsValidationService {
  static String? validateHeadline(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'News headline is required.';
    }
    return null;
  }

  static String? validateBody(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'News body / incident details are required.';
    }
    return null;
  }

  Future<NewsValidationResult> validateDraft(
    NewsDraft draft,
    MediaStorageService mediaStorage, {
    int maxPhotoSizeBytes = MediaStorageService.defaultMaxPhotoSizeBytes,
    int maxVideoSizeBytes = MediaStorageService.defaultMaxVideoSizeBytes,
    int maxAudioSizeBytes = MediaStorageService.defaultMaxAudioSizeBytes,
    int maxAudioDurationSeconds =
        MediaStorageService.defaultMaxAudioDurationSeconds,
  }) async {
    final headlineErr = validateHeadline(draft.headline);
    final bodyErr = validateBody(draft.incidentDetails);
    final mediaErrors = <String, String>{};

    for (final media in draft.mediaAttachments) {
      final path = media.localFilePath;
      if (path == null || path.isEmpty) {
        mediaErrors[media.id] =
            '${media.fileName}: Local media path is missing.';
        continue;
      }

      final file = File(path);
      try {
        if (media.mediaType == MediaType.video) {
          await mediaStorage.validateVideoFile(
            file,
            maxSizeBytes: maxVideoSizeBytes,
          );
        } else if (media.mediaType == MediaType.audio) {
          await mediaStorage.validateAudioFile(
            file,
            maxSizeBytes: maxAudioSizeBytes,
            durationSeconds: media.durationSeconds,
            maxDurationSeconds: maxAudioDurationSeconds,
          );
        } else {
          await mediaStorage.validatePhotoFile(
            file,
            maxSizeBytes: maxPhotoSizeBytes,
          );
        }
      } on MediaValidationException catch (e) {
        mediaErrors[media.id] = '${media.fileName}: ${e.message}';
      } catch (e) {
        mediaErrors[media.id] = '${media.fileName}: $e';
      }
    }

    final voice = draft.voiceDispatch;
    if (voice != null) {
      final path = voice.localFilePath;
      if (path == null || path.isEmpty) {
        mediaErrors[voice.id] =
            '${voice.fileName}: Local audio recording path is missing.';
      } else {
        try {
          await mediaStorage.validateAudioFile(
            File(path),
            maxSizeBytes: maxAudioSizeBytes,
            durationSeconds: voice.durationSeconds,
            maxDurationSeconds: maxAudioDurationSeconds,
          );
        } on MediaValidationException catch (e) {
          mediaErrors[voice.id] = '${voice.fileName}: ${e.message}';
        } catch (e) {
          mediaErrors[voice.id] = '${voice.fileName}: $e';
        }
      }
    }

    return NewsValidationResult(
      headlineError: headlineErr,
      bodyError: bodyErr,
      mediaErrors: mediaErrors,
    );
  }
}

