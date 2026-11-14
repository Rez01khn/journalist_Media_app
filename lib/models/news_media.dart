/// Type of media attached to field stories.
enum MediaType {
  image,
  video,
  audio,
  thumbnail,
  document;

  String toValue() => name;

  static MediaType fromString(String value) {
    return MediaType.values.firstWhere(
      (m) => m.name.toLowerCase() == value.toLowerCase(),
      orElse: () => MediaType.image,
    );
  }
}

/// Represents a media file captured in the field.
///
/// CRITICAL ARCHITECTURAL RULE:
/// Original images, videos, voice recordings, and thumbnails belong in the
/// individual reporter's personal Google Drive. The app database stores only the
/// metadata and the Google Drive file references ([driveFileId]).
/// Original media is never copied to the existing Laravel website database.
class NewsMedia {
  final String id;
  final String fileName;
  final String? localFilePath; // Local temporary path before or during Drive sync
  final String? driveFileId; // Reporter-owned Google Drive File ID
  final String? driveWebViewLink; // Google Drive Web View Link
  final String? driveDownloadLink;
  final String mimeType;
  final int? fileSizeBytes;
  final int? durationSeconds;
  final MediaType mediaType;
  final bool isUploadedToDrive;
  final String? uploadErrorMessage;
  final String? reporterGoogleAccountEmail;
  final DateTime createdAt;

  // Server Media Registration (Laravel backend metadata)
  final bool isRegisteredOnServer;
  final String? serverMediaId;
  final String? serverRegistrationError;
  final String? serverRegistrationStatus; // 'pending', 'registered', 'failed', 'duplicate'

  const NewsMedia({
    required this.id,
    required this.fileName,
    this.localFilePath,
    this.driveFileId,
    this.driveWebViewLink,
    this.driveDownloadLink,
    required this.mimeType,
    this.fileSizeBytes,
    this.durationSeconds,
    required this.mediaType,
    this.isUploadedToDrive = false,
    this.uploadErrorMessage,
    this.reporterGoogleAccountEmail,
    required this.createdAt,
    this.isRegisteredOnServer = false,
    this.serverMediaId,
    this.serverRegistrationError,
    this.serverRegistrationStatus,
  });

  NewsMedia copyWith({
    String? id,
    String? fileName,
    String? localFilePath,
    String? driveFileId,
    String? driveWebViewLink,
    String? driveDownloadLink,
    String? mimeType,
    int? fileSizeBytes,
    int? durationSeconds,
    MediaType? mediaType,
    bool? isUploadedToDrive,
    String? uploadErrorMessage,
    bool clearUploadError = false,
    String? reporterGoogleAccountEmail,
    DateTime? createdAt,
    bool? isRegisteredOnServer,
    String? serverMediaId,
    String? serverRegistrationError,
    bool clearServerError = false,
    String? serverRegistrationStatus,
  }) {
    return NewsMedia(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      localFilePath: localFilePath ?? this.localFilePath,
      driveFileId: driveFileId ?? this.driveFileId,
      driveWebViewLink: driveWebViewLink ?? this.driveWebViewLink,
      driveDownloadLink: driveDownloadLink ?? this.driveDownloadLink,
      mimeType: mimeType ?? this.mimeType,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      mediaType: mediaType ?? this.mediaType,
      isUploadedToDrive: isUploadedToDrive ?? this.isUploadedToDrive,
      uploadErrorMessage: clearUploadError
          ? null
          : (uploadErrorMessage ?? this.uploadErrorMessage),
      reporterGoogleAccountEmail:
          reporterGoogleAccountEmail ?? this.reporterGoogleAccountEmail,
      createdAt: createdAt ?? this.createdAt,
      isRegisteredOnServer: isRegisteredOnServer ?? this.isRegisteredOnServer,
      serverMediaId: serverMediaId ?? this.serverMediaId,
      serverRegistrationError: clearServerError
          ? null
          : (serverRegistrationError ?? this.serverRegistrationError),
      serverRegistrationStatus:
          serverRegistrationStatus ?? this.serverRegistrationStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'local_file_path': localFilePath,
      'drive_file_id': driveFileId,
      'drive_web_view_link': driveWebViewLink,
      'drive_download_link': driveDownloadLink,
      'mime_type': mimeType,
      'file_size_bytes': fileSizeBytes,
      'duration_seconds': durationSeconds,
      'media_type': mediaType.toValue(),
      'is_uploaded_to_drive': isUploadedToDrive,
      'upload_error_message': uploadErrorMessage,
      'reporter_google_account_email': reporterGoogleAccountEmail,
      'created_at': createdAt.toIso8601String(),
      'is_registered_on_server': isRegisteredOnServer,
      'server_media_id': serverMediaId,
      'server_registration_error': serverRegistrationError,
      'server_registration_status': serverRegistrationStatus,
    };
  }

  factory NewsMedia.fromJson(Map<String, dynamic> json) {
    return NewsMedia(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      localFilePath: json['local_file_path'] as String?,
      driveFileId: json['drive_file_id'] as String?,
      driveWebViewLink: json['drive_web_view_link'] as String?,
      driveDownloadLink: json['drive_download_link'] as String?,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      fileSizeBytes: json['file_size_bytes'] as int?,
      durationSeconds: json['duration_seconds'] as int?,
      mediaType: MediaType.fromString(json['media_type'] as String? ?? 'image'),
      isUploadedToDrive: json['is_uploaded_to_drive'] as bool? ?? false,
      uploadErrorMessage: json['upload_error_message'] as String?,
      reporterGoogleAccountEmail:
          json['reporter_google_account_email'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isRegisteredOnServer: json['is_registered_on_server'] as bool? ?? false,
      serverMediaId: json['server_media_id']?.toString(),
      serverRegistrationError: json['server_registration_error'] as String?,
      serverRegistrationStatus: json['server_registration_status'] as String?,
    );
  }
}

