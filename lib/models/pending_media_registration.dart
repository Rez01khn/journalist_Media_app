/// Represents a pending media metadata registration waiting to be registered
/// against a server news story via `POST /api/v1/news/{news}/media`.
///
/// Preserves stable media UUID, Drive file ID, and Idempotency-Key across
/// network retries, failures, and app restarts.
class PendingMediaRegistration {
  final String id; // Unique record UUID
  final String serverNewsId;
  final String? newsUuid;
  final String? clientDraftUuid;
  final String mediaId; // Client media item ID
  final String driveFileId;
  final String mediaType; // 'image', 'video', 'audio'
  final String originalFilename;
  final String mimeType;
  final int fileSizeBytes;
  final int? durationSeconds;
  final String? attachmentRole;
  final int? displayOrder;
  final String? driveFolderId;
  final String? driveWebViewLink;
  final String? driveDownloadLink;
  final String? reporterGoogleEmail;
  final String status; // 'pending', 'registered', 'failed', 'duplicate'
  final String? serverMediaId;
  final String? errorMessage;
  final String? idempotencyKey;
  final DateTime createdAt;
  final DateTime? lastAttemptedAt;
  final int retryCount;

  const PendingMediaRegistration({
    required this.id,
    required this.serverNewsId,
    this.newsUuid,
    this.clientDraftUuid,
    required this.mediaId,
    required this.driveFileId,
    required this.mediaType,
    required this.originalFilename,
    required this.mimeType,
    required this.fileSizeBytes,
    this.durationSeconds,
    this.attachmentRole,
    this.displayOrder,
    this.driveFolderId,
    this.driveWebViewLink,
    this.driveDownloadLink,
    this.reporterGoogleEmail,
    required this.status,
    this.serverMediaId,
    this.errorMessage,
    this.idempotencyKey,
    required this.createdAt,
    this.lastAttemptedAt,
    this.retryCount = 0,
  });

  PendingMediaRegistration copyWith({
    String? id,
    String? serverNewsId,
    String? newsUuid,
    String? clientDraftUuid,
    String? mediaId,
    String? driveFileId,
    String? mediaType,
    String? originalFilename,
    String? mimeType,
    int? fileSizeBytes,
    int? durationSeconds,
    String? attachmentRole,
    int? displayOrder,
    String? driveFolderId,
    String? driveWebViewLink,
    String? driveDownloadLink,
    String? reporterGoogleEmail,
    String? status,
    String? serverMediaId,
    String? errorMessage,
    String? idempotencyKey,
    DateTime? createdAt,
    DateTime? lastAttemptedAt,
    int? retryCount,
  }) {
    return PendingMediaRegistration(
      id: id ?? this.id,
      serverNewsId: serverNewsId ?? this.serverNewsId,
      newsUuid: newsUuid ?? this.newsUuid,
      clientDraftUuid: clientDraftUuid ?? this.clientDraftUuid,
      mediaId: mediaId ?? this.mediaId,
      driveFileId: driveFileId ?? this.driveFileId,
      mediaType: mediaType ?? this.mediaType,
      originalFilename: originalFilename ?? this.originalFilename,
      mimeType: mimeType ?? this.mimeType,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      attachmentRole: attachmentRole ?? this.attachmentRole,
      displayOrder: displayOrder ?? this.displayOrder,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      driveWebViewLink: driveWebViewLink ?? this.driveWebViewLink,
      driveDownloadLink: driveDownloadLink ?? this.driveDownloadLink,
      reporterGoogleEmail: reporterGoogleEmail ?? this.reporterGoogleEmail,
      status: status ?? this.status,
      serverMediaId: serverMediaId ?? this.serverMediaId,
      errorMessage: errorMessage ?? this.errorMessage,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toSqliteRow() {
    return {
      'id': id,
      'server_news_id': serverNewsId,
      'news_uuid': newsUuid,
      'client_draft_uuid': clientDraftUuid,
      'media_id': mediaId,
      'drive_file_id': driveFileId,
      'media_type': mediaType,
      'original_filename': originalFilename,
      'mime_type': mimeType,
      'file_size_bytes': fileSizeBytes,
      'duration_seconds': durationSeconds,
      'attachment_role': attachmentRole,
      'display_order': displayOrder,
      'drive_folder_id': driveFolderId,
      'drive_web_view_link': driveWebViewLink,
      'drive_download_link': driveDownloadLink,
      'reporter_google_email': reporterGoogleEmail,
      'status': status,
      'server_media_id': serverMediaId,
      'error_message': errorMessage,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
      'last_attempted_at': lastAttemptedAt?.toIso8601String(),
      'retry_count': retryCount,
    };
  }

  factory PendingMediaRegistration.fromSqliteRow(Map<String, dynamic> row) {
    return PendingMediaRegistration(
      id: row['id'] as String,
      serverNewsId: row['server_news_id'] as String,
      newsUuid: row['news_uuid'] as String?,
      clientDraftUuid: row['client_draft_uuid'] as String?,
      mediaId: row['media_id'] as String,
      driveFileId: row['drive_file_id'] as String,
      mediaType: row['media_type'] as String,
      originalFilename: row['original_filename'] as String,
      mimeType: row['mime_type'] as String,
      fileSizeBytes: row['file_size_bytes'] as int,
      durationSeconds: row['duration_seconds'] as int?,
      attachmentRole: row['attachment_role'] as String?,
      displayOrder: row['display_order'] as int?,
      driveFolderId: row['drive_folder_id'] as String?,
      driveWebViewLink: row['drive_web_view_link'] as String?,
      driveDownloadLink: row['drive_download_link'] as String?,
      reporterGoogleEmail: row['reporter_google_email'] as String?,
      status: row['status'] as String? ?? 'pending',
      serverMediaId: row['server_media_id'] as String?,
      errorMessage: row['error_message'] as String?,
      idempotencyKey: row['idempotency_key'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      lastAttemptedAt: row['last_attempted_at'] != null
          ? DateTime.parse(row['last_attempted_at'] as String)
          : null,
      retryCount: row['retry_count'] as int? ?? 0,
    );
  }
}
