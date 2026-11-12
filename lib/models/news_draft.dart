import 'package:journalist_app_1/models/news_media.dart';

/// Status of synchronization between local SQLite draft and reporter's Google Drive.
enum DraftSyncStatus {
  synced,
  syncing,
  pending,
  failed;

  String get displayName {
    switch (this) {
      case DraftSyncStatus.synced:
        return 'Synced';
      case DraftSyncStatus.syncing:
        return 'Syncing';
      case DraftSyncStatus.pending:
        return 'Pending';
      case DraftSyncStatus.failed:
        return 'Sync Failed';
    }
  }
}

/// Represents a local field news draft stored offline before editorial submission.
///
/// CRITICAL ARCHITECTURAL RULE:
/// Reporters working in areas with intermittent connectivity save drafts locally.
/// Media captured in drafts is staged for upload to the reporter's personal
/// Google Drive once online.
class NewsDraft {
  final String id;
  final String reporterId;
  final String headline;
  final String category;
  final String location;
  final String incidentDetails;
  final List<NewsMedia> mediaAttachments;
  final NewsMedia? voiceDispatch;
  final String? aiAssistedHeadline;
  final String? aiAssistedBody;
  final bool isAiAssisted;
  final DateTime lastSavedAt;
  final bool isSyncedWithDrive;
  final String? driveFolderId;
  final String? driveFileId;
  final DraftSyncStatus driveSyncStatus;
  final DateTime? lastSyncedAt;
  final String? syncErrorMessage;

  const NewsDraft({
    required this.id,
    required this.reporterId,
    required this.headline,
    required this.category,
    required this.location,
    required this.incidentDetails,
    this.mediaAttachments = const [],
    this.voiceDispatch,
    this.aiAssistedHeadline,
    this.aiAssistedBody,
    this.isAiAssisted = false,
    required this.lastSavedAt,
    this.isSyncedWithDrive = false,
    this.driveFolderId,
    this.driveFileId,
    this.driveSyncStatus = DraftSyncStatus.pending,
    this.lastSyncedAt,
    this.syncErrorMessage,
  });

  NewsDraft copyWith({
    String? id,
    String? reporterId,
    String? headline,
    String? category,
    String? location,
    String? incidentDetails,
    List<NewsMedia>? mediaAttachments,
    NewsMedia? voiceDispatch,
    bool clearVoiceDispatch = false,
    String? aiAssistedHeadline,
    String? aiAssistedBody,
    bool? isAiAssisted,
    DateTime? lastSavedAt,
    bool? isSyncedWithDrive,
    String? driveFolderId,
    String? driveFileId,
    DraftSyncStatus? driveSyncStatus,
    DateTime? lastSyncedAt,
    String? syncErrorMessage,
  }) {
    return NewsDraft(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      headline: headline ?? this.headline,
      category: category ?? this.category,
      location: location ?? this.location,
      incidentDetails: incidentDetails ?? this.incidentDetails,
      mediaAttachments: mediaAttachments ?? this.mediaAttachments,
      voiceDispatch: clearVoiceDispatch
          ? null
          : (voiceDispatch ?? this.voiceDispatch),
      aiAssistedHeadline: aiAssistedHeadline ?? this.aiAssistedHeadline,
      aiAssistedBody: aiAssistedBody ?? this.aiAssistedBody,
      isAiAssisted: isAiAssisted ?? this.isAiAssisted,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      isSyncedWithDrive: isSyncedWithDrive ?? this.isSyncedWithDrive,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      driveFileId: driveFileId ?? this.driveFileId,
      driveSyncStatus: driveSyncStatus ?? this.driveSyncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncErrorMessage: syncErrorMessage ?? this.syncErrorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporter_id': reporterId,
      'headline': headline,
      'category': category,
      'location': location,
      'incident_details': incidentDetails,
      'media_attachments': mediaAttachments.map((m) => m.toJson()).toList(),
      'voice_dispatch': voiceDispatch?.toJson(),
      'ai_assisted_headline': aiAssistedHeadline,
      'ai_assisted_body': aiAssistedBody,
      'is_ai_assisted': isAiAssisted,
      'last_saved_at': lastSavedAt.toIso8601String(),
      'is_synced_with_drive': isSyncedWithDrive,
      'drive_folder_id': driveFolderId,
      'drive_file_id': driveFileId,
      'drive_sync_status': driveSyncStatus.name,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'sync_error_message': syncErrorMessage,
    };
  }

  factory NewsDraft.fromJson(Map<String, dynamic> json) {
    final syncStatusStr = json['drive_sync_status'] as String?;
    final isSyncedFlag = json['is_synced_with_drive'] as bool? ?? false;
    final parsedStatus = syncStatusStr != null
        ? DraftSyncStatus.values.firstWhere(
            (e) => e.name == syncStatusStr,
            orElse: () =>
                isSyncedFlag ? DraftSyncStatus.synced : DraftSyncStatus.pending,
          )
        : (isSyncedFlag ? DraftSyncStatus.synced : DraftSyncStatus.pending);

    return NewsDraft(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String,
      headline: json['headline'] as String? ?? '',
      category: json['category'] as String? ?? '',
      location: json['location'] as String? ?? '',
      incidentDetails: json['incident_details'] as String? ?? '',
      mediaAttachments:
          (json['media_attachments'] as List<dynamic>?)
              ?.map((item) => NewsMedia.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      voiceDispatch: json['voice_dispatch'] != null
          ? NewsMedia.fromJson(json['voice_dispatch'] as Map<String, dynamic>)
          : null,
      aiAssistedHeadline: json['ai_assisted_headline'] as String?,
      aiAssistedBody: json['ai_assisted_body'] as String?,
      isAiAssisted: json['is_ai_assisted'] as bool? ?? false,
      lastSavedAt: json['last_saved_at'] != null
          ? DateTime.parse(json['last_saved_at'] as String)
          : DateTime.now(),
      isSyncedWithDrive: isSyncedFlag || parsedStatus == DraftSyncStatus.synced,
      driveFolderId: json['drive_folder_id'] as String?,
      driveFileId: json['drive_file_id'] as String?,
      driveSyncStatus: parsedStatus,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.tryParse(json['last_synced_at'] as String)
          : null,
      syncErrorMessage: json['sync_error_message'] as String?,
    );
  }
}
