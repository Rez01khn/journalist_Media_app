import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown when a picked or recorded media file fails format or size validation.
class MediaValidationException implements Exception {
  final String message;
  const MediaValidationException(this.message);

  @override
  String toString() => message;
}

/// Service responsible for managing local storage of captured/picked photos, videos, and audio.
/// Ensures original media files are persisted in app documents storage so they
/// survive app restarts, cache wipes, and offline periods.
class MediaStorageService {
  /// Default maximum allowed photo size (25 MB), configurable per call.
  static const int defaultMaxPhotoSizeBytes = 25 * 1024 * 1024;

  /// Default maximum allowed video size (100 MB), configurable per call.
  static const int defaultMaxVideoSizeBytes = 100 * 1024 * 1024;

  /// Default maximum allowed audio file size (25 MB), configurable per call.
  static const int defaultMaxAudioSizeBytes = 25 * 1024 * 1024;

  /// Default maximum allowed audio duration in seconds (15 minutes), configurable per call.
  static const int defaultMaxAudioDurationSeconds = 15 * 60;

  /// Supported photo file extensions for field reporting.
  static const List<String> allowedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  ];

  /// Supported video file extensions for field reporting.
  static const List<String> allowedVideoExtensions = [
    '.mp4',
    '.mov',
    '.m4v',
    '.3gp',
    '.webm',
    '.avi',
    '.mkv',
  ];

  /// Supported audio file extensions for field voice dispatches.
  static const List<String> allowedAudioExtensions = [
    '.m4a',
    '.aac',
    '.wav',
    '.mp3',
    '.ogg',
    '.opus',
    '.amr',
  ];

  final Directory? _customBaseDir;

  MediaStorageService({Directory? customBaseDir})
      : _customBaseDir = customBaseDir;

  Future<Directory> _getDraftMediaDir(String draftId) async {
    Directory baseDir;
    if (_customBaseDir != null) {
      baseDir = _customBaseDir;
    } else if (Platform.environment.containsKey('FLUTTER_TEST')) {
      baseDir = Directory.systemTemp;
    } else {
      try {
        baseDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = Directory.systemTemp;
      }
    }
    final mediaDir = Directory(p.join(baseDir.path, 'media', 'drafts', draftId));
    if (!mediaDir.existsSync()) {
      mediaDir.createSync(recursive: true);
    }
    return mediaDir;
  }

  /// Validates a photo file's existence, format, and size.
  Future<void> validatePhotoFile(
    File sourceFile, {
    int maxSizeBytes = defaultMaxPhotoSizeBytes,
  }) async {
    if (!sourceFile.existsSync()) {
      throw const MediaValidationException(
        'Attached photo file could not be found on device storage.',
      );
    }

    final ext = p.extension(sourceFile.path).toLowerCase();
    if (ext.isEmpty || !allowedImageExtensions.contains(ext)) {
      throw MediaValidationException(
        'Unsupported photo format (${ext.isEmpty ? "unknown" : ext}). Allowed formats: JPG, JPEG, PNG, WEBP, HEIC.',
      );
    }

    final sizeBytes = sourceFile.lengthSync();
    if (sizeBytes <= 0) {
      throw const MediaValidationException(
        'Attached photo file is empty (0 bytes).',
      );
    }

    if (sizeBytes > maxSizeBytes) {
      final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      final actualMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      throw MediaValidationException(
        'Photo file size ($actualMb MB) exceeds maximum limit of $maxMb MB.',
      );
    }
  }

  /// Validates a video file's existence, format, and size before persisting.
  Future<void> validateVideoFile(
    File sourceFile, {
    int maxSizeBytes = defaultMaxVideoSizeBytes,
  }) async {
    if (!await sourceFile.exists()) {
      throw const MediaValidationException(
        'Selected video file could not be found on device storage.',
      );
    }

    final ext = p.extension(sourceFile.path).toLowerCase();
    if (ext.isEmpty || !allowedVideoExtensions.contains(ext)) {
      throw MediaValidationException(
        'Unsupported video format (${ext.isEmpty ? "unknown" : ext}). Allowed formats: MP4, MOV, M4V, 3GP, WEBM.',
      );
    }

    final sizeBytes = await sourceFile.length();
    if (sizeBytes <= 0) {
      throw const MediaValidationException(
        'Selected video file is empty (0 bytes).',
      );
    }

    if (sizeBytes > maxSizeBytes) {
      final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      final actualMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      throw MediaValidationException(
        'Video file size ($actualMb MB) exceeds maximum limit of $maxMb MB.',
      );
    }
  }

  /// Resolves the MIME type for a video file path.
  String resolveVideoMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.mov':
        return 'video/quicktime';
      case '.3gp':
        return 'video/3gpp';
      case '.webm':
        return 'video/webm';
      case '.avi':
        return 'video/x-msvideo';
      case '.mkv':
        return 'video/x-matroska';
      case '.m4v':
      case '.mp4':
      default:
        return 'video/mp4';
    }
  }

  /// Copies an image file from cache/camera/gallery to app-managed persistent storage.
  Future<File> persistDraftPhoto({
    required File sourceFile,
    required String draftId,
  }) async {
    final targetDir = await _getDraftMediaDir(draftId);
    final ext = p.extension(sourceFile.path).isNotEmpty
        ? p.extension(sourceFile.path)
        : '.jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = sourceFile.path.hashCode.abs() % 10000;
    final targetFileName = 'photo_${draftId}_${timestamp}_$randomSuffix$ext';
    final targetPath = p.join(targetDir.path, targetFileName);

    return await sourceFile.copy(targetPath);
  }

  /// Validates and copies a video file from camera/gallery into app-managed persistent storage.
  Future<File> persistDraftVideo({
    required File sourceFile,
    required String draftId,
    int maxSizeBytes = defaultMaxVideoSizeBytes,
  }) async {
    await validateVideoFile(sourceFile, maxSizeBytes: maxSizeBytes);

    final targetDir = await _getDraftMediaDir(draftId);
    final ext = p.extension(sourceFile.path).toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = sourceFile.path.hashCode.abs() % 10000;
    final targetFileName = 'video_${draftId}_${timestamp}_$randomSuffix$ext';
    final targetPath = p.join(targetDir.path, targetFileName);

    return await sourceFile.copy(targetPath);
  }

  /// Validates an audio file's existence, format, size, and duration before persisting.
  Future<void> validateAudioFile(
    File sourceFile, {
    int maxSizeBytes = defaultMaxAudioSizeBytes,
    int? durationSeconds,
    int maxDurationSeconds = defaultMaxAudioDurationSeconds,
  }) async {
    if (!sourceFile.existsSync()) {
      throw const MediaValidationException(
        'Recorded audio file could not be found on device storage.',
      );
    }

    final ext = p.extension(sourceFile.path).toLowerCase();
    if (ext.isEmpty || !allowedAudioExtensions.contains(ext)) {
      throw MediaValidationException(
        'Unsupported audio format (${ext.isEmpty ? "unknown" : ext}). Allowed formats: M4A, AAC, WAV, MP3, OGG.',
      );
    }

    final sizeBytes = sourceFile.lengthSync();
    if (sizeBytes <= 0) {
      throw const MediaValidationException(
        'Recorded audio file is empty (0 bytes).',
      );
    }

    if (sizeBytes > maxSizeBytes) {
      final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      final actualMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      throw MediaValidationException(
        'Audio file size ($actualMb MB) exceeds maximum limit of $maxMb MB.',
      );
    }

    if (durationSeconds != null && durationSeconds > maxDurationSeconds) {
      final maxMins = (maxDurationSeconds / 60).toStringAsFixed(0);
      throw MediaValidationException(
        'Audio recording duration (${durationSeconds}s) exceeds maximum limit of $maxMins minutes.',
      );
    }
  }

  /// Resolves the MIME type for an audio file path.
  String resolveAudioMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.wav':
        return 'audio/wav';
      case '.mp3':
        return 'audio/mpeg';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.amr':
        return 'audio/amr';
      case '.m4a':
      default:
        return 'audio/mp4';
    }
  }

  /// Creates a staging path inside app-managed draft storage for an active recording.
  Future<String> createTempAudioRecordingPath(
    String draftId, {
    String extension = '.m4a',
  }) async {
    final targetDir = await _getDraftMediaDir(draftId);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(targetDir.path, 'recording_stage_${draftId}_$timestamp$extension');
  }

  /// Validates and persists a voice recording file in app-managed local storage.
  Future<File> persistDraftAudio({
    required File sourceFile,
    required String draftId,
    int maxSizeBytes = defaultMaxAudioSizeBytes,
    int? durationSeconds,
    int maxDurationSeconds = defaultMaxAudioDurationSeconds,
  }) async {
    await validateAudioFile(
      sourceFile,
      maxSizeBytes: maxSizeBytes,
      durationSeconds: durationSeconds,
      maxDurationSeconds: maxDurationSeconds,
    );

    final targetDir = await _getDraftMediaDir(draftId);
    final ext = p.extension(sourceFile.path).toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = sourceFile.path.hashCode.abs() % 10000;
    final targetFileName = 'voice_${draftId}_${timestamp}_$randomSuffix$ext';
    final targetPath = p.join(targetDir.path, targetFileName);

    if (p.equals(sourceFile.path, targetPath)) {
      return sourceFile;
    }

    final copied = sourceFile.copySync(targetPath);
    if (p.basename(sourceFile.path).startsWith('recording_stage_')) {
      try {
        sourceFile.deleteSync();
      } catch (_) {}
    }
    return copied;
  }

  /// Safely removes a local media file if the reporter detaches or replaces it.
  Future<void> deleteLocalMedia(String? localFilePath) async {
    if (localFilePath == null || localFilePath.isEmpty) return;
    try {
      final file = File(localFilePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Ignored
    }
  }

  /// Cleans up all media files for a discarded draft.
  Future<void> cleanupDraftMedia(String draftId) async {
    try {
      final dir = await _getDraftMediaDir(draftId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Ignored
    }
  }
}

