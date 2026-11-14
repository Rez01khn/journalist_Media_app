import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/models/news_status.dart';

/// Editorial status of media attachments registration against the Laravel backend.
enum MediaRegistrationStatus {
  none,
  pending,
  partial,
  complete,
  failed;

  String toValue() => name;

  static MediaRegistrationStatus fromString(String? value) {
    if (value == null) return MediaRegistrationStatus.none;
    return MediaRegistrationStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == value.toLowerCase(),
      orElse: () => MediaRegistrationStatus.none,
    );
  }
}

/// Represents an official submitted news story in the reporting workflow.
///
/// CRITICAL ARCHITECTURAL RULES:
/// 1. Stored in the independent MySQL app database for user accounts, workflow statuses,
///    and Google Drive file references.
/// 2. Original media resides strictly in each reporter's personal Google Drive.
/// 3. The existing Laravel news website will only receive finalized news content
///    and essential editorial metadata ([isExportedToLaravelWebsite]). Original media
///    must never be copied to the existing Laravel website database.
class News {
  final String id;
  final String trackingCode; // e.g. REP-101
  final String reporterId;
  final String reporterName;
  final String headline;
  final String category;
  final String location;
  final String incidentDetails;
  final NewsStatus status;
  final List<NewsMedia> mediaAttachments;
  final NewsMedia? voiceDispatch;
  final NewsMedia? thumbnail;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final DateTime? publishedAt;
  final String? rejectionReason;
  final String? editorialNotes;
  final bool isAiAssisted;
  final MediaRegistrationStatus mediaRegistrationStatus;

  // Future Laravel news website integration metadata
  final bool isExportedToLaravelWebsite;
  final String? laravelWebsitePostId;

  const News({
    required this.id,
    required this.trackingCode,
    required this.reporterId,
    required this.reporterName,
    required this.headline,
    required this.category,
    required this.location,
    required this.incidentDetails,
    required this.status,
    this.mediaAttachments = const [],
    this.voiceDispatch,
    this.thumbnail,
    required this.submittedAt,
    this.reviewedAt,
    this.publishedAt,
    this.rejectionReason,
    this.editorialNotes,
    this.isAiAssisted = false,
    this.mediaRegistrationStatus = MediaRegistrationStatus.none,
    this.isExportedToLaravelWebsite = false,
    this.laravelWebsitePostId,
  });

  News copyWith({
    String? id,
    String? trackingCode,
    String? reporterId,
    String? reporterName,
    String? headline,
    String? category,
    String? location,
    String? incidentDetails,
    NewsStatus? status,
    List<NewsMedia>? mediaAttachments,
    NewsMedia? voiceDispatch,
    NewsMedia? thumbnail,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    DateTime? publishedAt,
    String? rejectionReason,
    String? editorialNotes,
    bool? isAiAssisted,
    MediaRegistrationStatus? mediaRegistrationStatus,
    bool? isExportedToLaravelWebsite,
    String? laravelWebsitePostId,
  }) {
    return News(
      id: id ?? this.id,
      trackingCode: trackingCode ?? this.trackingCode,
      reporterId: reporterId ?? this.reporterId,
      reporterName: reporterName ?? this.reporterName,
      headline: headline ?? this.headline,
      category: category ?? this.category,
      location: location ?? this.location,
      incidentDetails: incidentDetails ?? this.incidentDetails,
      status: status ?? this.status,
      mediaAttachments: mediaAttachments ?? this.mediaAttachments,
      voiceDispatch: voiceDispatch ?? this.voiceDispatch,
      thumbnail: thumbnail ?? this.thumbnail,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      editorialNotes: editorialNotes ?? this.editorialNotes,
      isAiAssisted: isAiAssisted ?? this.isAiAssisted,
      mediaRegistrationStatus:
          mediaRegistrationStatus ?? this.mediaRegistrationStatus,
      isExportedToLaravelWebsite:
          isExportedToLaravelWebsite ?? this.isExportedToLaravelWebsite,
      laravelWebsitePostId: laravelWebsitePostId ?? this.laravelWebsitePostId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tracking_code': trackingCode,
      'reporter_id': reporterId,
      'reporter_name': reporterName,
      'headline': headline,
      'category': category,
      'location': location,
      'incident_details': incidentDetails,
      'status': status.toValue(),
      'media_attachments': mediaAttachments.map((m) => m.toJson()).toList(),
      'voice_dispatch': voiceDispatch?.toJson(),
      'thumbnail': thumbnail?.toJson(),
      'submitted_at': submittedAt.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
      'rejection_reason': rejectionReason,
      'editorial_notes': editorialNotes,
      'is_ai_assisted': isAiAssisted,
      'media_registration_status': mediaRegistrationStatus.toValue(),
      'is_exported_to_laravel_website': isExportedToLaravelWebsite,
      'laravel_website_post_id': laravelWebsitePostId,
    };
  }

  factory News.fromJson(Map<String, dynamic> json) {
    return News(
      id: json['id']?.toString() ?? '',
      trackingCode: json['tracking_code'] as String? ?? 'REP-000',
      reporterId: json['reporter_id']?.toString() ?? 'user-001',
      reporterName: json['reporter_name'] as String? ?? 'Reporter',
      headline: json['headline'] as String? ?? '',
      category: json['category'] as String? ?? '',
      location: json['location'] as String? ?? '',
      incidentDetails: json['incident_details'] as String? ?? '',
      status: NewsStatus.fromString(json['status'] as String? ?? 'draft'),
      mediaAttachments: (json['media_attachments'] as List<dynamic>?)
              ?.map((item) => NewsMedia.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      voiceDispatch: json['voice_dispatch'] != null
          ? NewsMedia.fromJson(json['voice_dispatch'] as Map<String, dynamic>)
          : null,
      thumbnail: json['thumbnail'] != null
          ? NewsMedia.fromJson(json['thumbnail'] as Map<String, dynamic>)
          : null,
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      rejectionReason: json['rejection_reason'] as String?,
      editorialNotes: json['editorial_notes'] as String?,
      isAiAssisted: json['is_ai_assisted'] as bool? ?? false,
      mediaRegistrationStatus: MediaRegistrationStatus.fromString(
        json['media_registration_status'] as String?,
      ),
      isExportedToLaravelWebsite:
          json['is_exported_to_laravel_website'] as bool? ?? false,
      laravelWebsitePostId: json['laravel_website_post_id'] as String?,
    );
  }
}

