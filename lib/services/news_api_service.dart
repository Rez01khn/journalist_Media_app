import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:journalist_app_1/core/constants/app_config.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_status.dart';

/// Typed exception for news submission API failures.
class NewsApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;
  final Map<String, dynamic> details;

  const NewsApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
    this.details = const {},
  });

  /// Whether this failure is recoverable with a retry (network/timeout/5xx).
  bool get isRetryable =>
      code == 'NETWORK_ERROR' ||
      code == 'REQUEST_TIMEOUT' ||
      code == 'SERVER_ERROR' ||
      code == 'REQUEST_IN_PROGRESS';

  /// Whether this failure means the submission was rejected (4xx, not idempotent replay).
  bool get isRejected => statusCode != null && statusCode! >= 400 && statusCode! < 500;

  @override
  String toString() => 'NewsApiException($code, status=$statusCode): $message';
}

/// Server-side result returned after a successful media metadata registration.
class NewsMediaRegistrationResult {
  final String serverId;
  final String serverUuid;
  final String serverNewsId;
  final String driveFileId;
  final String mediaType;
  final String uploadStatus;
  final bool idempotentReplay;
  final bool isDuplicate;

  const NewsMediaRegistrationResult({
    required this.serverId,
    required this.serverUuid,
    required this.serverNewsId,
    required this.driveFileId,
    required this.mediaType,
    required this.uploadStatus,
    this.idempotentReplay = false,
    this.isDuplicate = false,
  });
}

/// Server-side result returned after a successful news submission.
class NewsSubmissionResult {
  /// Server-assigned MySQL primary key (integer as string).
  final String serverId;

  /// Server-assigned UUID for the news record.
  final String serverUuid;

  /// Human-readable tracking code, e.g. `REP-20261114-0042`.
  final String trackingCode;

  /// Workflow status after submission — always `submitted`.
  final String status;

  /// Whether this response was replayed from an idempotency cache.
  final bool idempotentReplay;

  const NewsSubmissionResult({
    required this.serverId,
    required this.serverUuid,
    required this.trackingCode,
    required this.status,
    this.idempotentReplay = false,
  });

  factory NewsSubmissionResult.fromJson(
    Map<String, dynamic> data, {
    bool idempotentReplay = false,
  }) {
    return NewsSubmissionResult(
      serverId: data['id']?.toString() ?? '',
      serverUuid: data['uuid']?.toString() ?? '',
      trackingCode: data['tracking_code']?.toString() ?? '',
      status: data['status']?.toString() ?? 'submitted',
      idempotentReplay: idempotentReplay,
    );
  }
}

/// HTTP client for `POST /api/v1/news` on the Laravel Journalist Backend.
///
/// Completely separate from Google Drive OAuth and authentication services.
class NewsApiService {
  final http.Client _client;
  final String Function() _baseUrlResolver;
  final Duration _timeout;

  NewsApiService({
    http.Client? client,
    String Function()? baseUrlResolver,
    Duration timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _baseUrlResolver = baseUrlResolver ?? (() => AppConfig.apiBaseUrl),
        _timeout = timeout;

  /// Submits a news story to `POST /api/v1/news`.
  ///
  /// [accessToken] — Sanctum Bearer token from secure storage.
  /// [headline] — Required. Min 5, max 300 chars.
  /// [body] — Required. Min 20 chars.
  /// [category] — Optional category label.
  /// [location] — Optional location string.
  /// [clientDraftUuid] — Stable UUID of the local SQLite draft (used for
  ///   server-side duplicate detection across retries).
  /// [idempotencyKey] — Optional 1–64 char key for idempotency header.
  /// [driveFolderId] — Optional Google Drive folder ID for the draft.
  /// [driveDraftJsonFileId] — Optional Drive file ID for the draft JSON.
  /// [reporterGoogleEmail] — Optional Drive-linked email.
  /// [isAiAssisted] — Whether AI generated headline/body.
  /// [aiAssistedHeadline] — Optional AI headline.
  /// [aiAssistedBody] — Optional AI body.
  Future<NewsSubmissionResult> submitNews({
    required String accessToken,
    required String headline,
    required String body,
    String? category,
    String? location,
    String? clientDraftUuid,
    String? idempotencyKey,
    String? driveFolderId,
    String? driveDraftJsonFileId,
    String? reporterGoogleEmail,
    bool isAiAssisted = false,
    String? aiAssistedHeadline,
    String? aiAssistedBody,
  }) async {
    final baseUrl = _baseUrlResolver().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/news');

    final payload = <String, dynamic>{
      'headline': headline.trim(),
      'body': body.trim(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
      if (clientDraftUuid != null && clientDraftUuid.trim().isNotEmpty)
        'client_draft_uuid': clientDraftUuid.trim(),
      if (driveFolderId != null && driveFolderId.trim().isNotEmpty)
        'drive_folder_id': driveFolderId.trim(),
      if (driveDraftJsonFileId != null && driveDraftJsonFileId.trim().isNotEmpty)
        'drive_draft_json_file_id': driveDraftJsonFileId.trim(),
      if (reporterGoogleEmail != null && reporterGoogleEmail.trim().isNotEmpty)
        'reporter_google_email': reporterGoogleEmail.trim(),
      'is_ai_assisted': isAiAssisted,
      if (aiAssistedHeadline != null && aiAssistedHeadline.trim().isNotEmpty)
        'ai_assisted_headline': aiAssistedHeadline.trim(),
      if (aiAssistedBody != null && aiAssistedBody.trim().isNotEmpty)
        'ai_assisted_body': aiAssistedBody.trim(),
    };

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${accessToken.trim()}',
      'X-Client-Version': 'flutter-mobile/1.0.0',
    };

    // Attach idempotency key if provided (max 64 chars, enforced server-side too)
    final effectiveKey = idempotencyKey?.trim();
    if (effectiveKey != null && effectiveKey.isNotEmpty) {
      headers['Idempotency-Key'] = effectiveKey.substring(
        0,
        effectiveKey.length > 64 ? 64 : effectiveKey.length,
      );
    }

    http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on TimeoutException {
      throw const NewsApiException(
        code: 'REQUEST_TIMEOUT',
        message:
            'The server took too long to respond. Your story is saved locally and will retry automatically.',
      );
    } on SocketException {
      throw const NewsApiException(
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the newsroom server. Your story is saved locally and will retry when you are online.',
      );
    } on http.ClientException catch (e) {
      throw NewsApiException(
        code: 'NETWORK_ERROR',
        message: 'Network error (${e.message}). Story saved locally.',
      );
    }

    Map<String, dynamic> bodyJson;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      bodyJson = decoded;
    } catch (_) {
      throw NewsApiException(
        code: 'INVALID_RESPONSE',
        statusCode: response.statusCode,
        message: 'Unexpected response from server (HTTP ${response.statusCode}).',
      );
    }

    // 2xx success
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        bodyJson['success'] == true) {
      final data = bodyJson['data'];
      if (data is! Map<String, dynamic>) {
        throw NewsApiException(
          code: 'INVALID_RESPONSE',
          statusCode: response.statusCode,
          message: 'Server returned unexpected data format.',
        );
      }
      final meta = bodyJson['meta'];
      final idempotentReplay =
          meta is Map<String, dynamic> && meta['idempotent_replay'] == true;
      return NewsSubmissionResult.fromJson(data, idempotentReplay: idempotentReplay);
    }

    // Extract error info
    final errorObj = bodyJson['error'];
    final code = errorObj is Map<String, dynamic>
        ? (errorObj['code'] as String? ?? 'SUBMISSION_FAILED')
        : 'SUBMISSION_FAILED';
    final serverMsg = errorObj is Map<String, dynamic>
        ? (errorObj['message'] as String?)
        : null;
    final errors = errorObj is Map<String, dynamic>
        ? _extractFieldErrors(bodyJson['errors'])
        : <String, List<String>>{};

    if (response.statusCode == 401) {
      throw NewsApiException(
        code: 'UNAUTHENTICATED',
        statusCode: 401,
        message: serverMsg ?? 'Session expired. Please sign in again.',
      );
    }

    if (response.statusCode == 403) {
      throw NewsApiException(
        code: code,
        statusCode: 403,
        message: serverMsg ?? 'You do not have permission to submit news.',
      );
    }

    if (response.statusCode == 422) {
      throw NewsApiException(
        code: 'VALIDATION_ERROR',
        statusCode: 422,
        message: serverMsg ?? 'The submission contains invalid data.',
        fieldErrors: errors,
      );
    }

    if (response.statusCode >= 500) {
      throw NewsApiException(
        code: 'SERVER_ERROR',
        statusCode: response.statusCode,
        message:
            serverMsg ?? 'Server error (HTTP ${response.statusCode}). Please retry.',
      );
    }

    throw NewsApiException(
      code: code,
      statusCode: response.statusCode,
      message: serverMsg ?? 'Submission failed (HTTP ${response.statusCode}).',
      details: errorObj is Map<String, dynamic> ? errorObj : const {},
    );
  }

  /// Registers media metadata against an existing news story at `POST /api/v1/news/{news}/media`.
  Future<NewsMediaRegistrationResult> registerNewsMedia({
    required String accessToken,
    required String serverNewsId,
    required String driveFileId,
    required String mediaType,
    required String originalFilename,
    required String mimeType,
    required int fileSizeBytes,
    String? uuid,
    String? idempotencyKey,
    String? attachmentRole,
    int? displayOrder,
    int? durationSeconds,
    String? driveFolderId,
    String? driveWebViewLink,
    String? driveDownloadLink,
    String? reporterGoogleEmail,
    String? checksumSha256,
    DateTime? capturedAt,
  }) async {
    final baseUrl = _baseUrlResolver().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/news/$serverNewsId/media');

    final payload = <String, dynamic>{
      'drive_file_id': driveFileId.trim(),
      'media_type': mediaType.trim().toLowerCase(),
      'original_filename': originalFilename.trim(),
      'mime_type': mimeType.trim(),
      'file_size_bytes': fileSizeBytes,
      if (uuid != null && uuid.trim().isNotEmpty) 'uuid': uuid.trim(),
      if (attachmentRole != null && attachmentRole.trim().isNotEmpty)
        'attachment_role': attachmentRole.trim(),
      if (displayOrder != null) 'display_order': displayOrder,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (driveFolderId != null && driveFolderId.trim().isNotEmpty)
        'drive_folder_id': driveFolderId.trim(),
      if (driveWebViewLink != null && driveWebViewLink.trim().isNotEmpty)
        'drive_web_view_link': driveWebViewLink.trim(),
      if (driveDownloadLink != null && driveDownloadLink.trim().isNotEmpty)
        'drive_download_link': driveDownloadLink.trim(),
      if (reporterGoogleEmail != null && reporterGoogleEmail.trim().isNotEmpty)
        'reporter_google_email': reporterGoogleEmail.trim(),
      if (checksumSha256 != null && checksumSha256.trim().isNotEmpty)
        'checksum_sha256': checksumSha256.trim(),
      if (capturedAt != null) 'captured_at': capturedAt.toIso8601String(),
    };

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${accessToken.trim()}',
      'X-Client-Version': 'flutter-mobile/1.0.0',
    };

    final effectiveKey = idempotencyKey?.trim();
    if (effectiveKey != null && effectiveKey.isNotEmpty) {
      headers['Idempotency-Key'] = effectiveKey.substring(
        0,
        effectiveKey.length > 64 ? 64 : effectiveKey.length,
      );
    }

    http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on TimeoutException {
      throw const NewsApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'The media metadata registration request timed out.',
      );
    } on SocketException {
      throw const NewsApiException(
        code: 'NETWORK_ERROR',
        message: 'Unable to reach the newsroom server to register media metadata.',
      );
    } on http.ClientException catch (e) {
      throw NewsApiException(
        code: 'NETWORK_ERROR',
        message: 'Network error (${e.message}) while registering media metadata.',
      );
    }

    Map<String, dynamic> bodyJson;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      bodyJson = decoded;
    } catch (_) {
      throw NewsApiException(
        code: 'INVALID_RESPONSE',
        statusCode: response.statusCode,
        message: 'Unexpected response from server (HTTP ${response.statusCode}).',
      );
    }

    // 2xx success
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        bodyJson['success'] == true) {
      final data = bodyJson['data'] as Map<String, dynamic>? ?? {};
      final meta = bodyJson['meta'] as Map<String, dynamic>? ?? {};
      return NewsMediaRegistrationResult(
        serverId: data['id']?.toString() ?? '',
        serverUuid: data['uuid']?.toString() ?? '',
        serverNewsId: data['news_id']?.toString() ?? serverNewsId,
        driveFileId: data['drive_file_id']?.toString() ?? driveFileId,
        mediaType: data['media_type']?.toString() ?? mediaType,
        uploadStatus: data['upload_status']?.toString() ?? 'synced',
        idempotentReplay: meta['idempotent_replay'] == true,
        isDuplicate: false,
      );
    }

    // Error handling
    final errorObj = bodyJson['error'];
    final code = errorObj is Map<String, dynamic>
        ? (errorObj['code'] as String? ?? 'REGISTRATION_FAILED')
        : 'REGISTRATION_FAILED';
    final serverMsg = errorObj is Map<String, dynamic>
        ? (errorObj['message'] as String?)
        : null;
    final details = errorObj is Map<String, dynamic> && errorObj['details'] is Map<String, dynamic>
        ? (errorObj['details'] as Map<String, dynamic>)
        : <String, dynamic>{};

    // 409 Conflict: check for duplicate media
    if (response.statusCode == 409) {
      if (code == 'DUPLICATE_MEDIA' || code == 'DUPLICATE_MEDIA_UUID') {
        final existingId = details['existing_media_id']?.toString();
        final existingUuid = details['existing_media_uuid']?.toString();
        return NewsMediaRegistrationResult(
          serverId: existingId ?? '',
          serverUuid: existingUuid ?? '',
          serverNewsId: serverNewsId,
          driveFileId: driveFileId,
          mediaType: mediaType,
          uploadStatus: 'synced',
          idempotentReplay: false,
          isDuplicate: true,
        );
      }
      throw NewsApiException(
        code: code,
        statusCode: 409,
        message: serverMsg ?? 'A conflict occurred while registering media metadata.',
        details: details,
      );
    }

    if (response.statusCode == 401) {
      throw NewsApiException(
        code: 'UNAUTHENTICATED',
        statusCode: 401,
        message: serverMsg ?? 'Session expired. Please sign in again.',
        details: details,
      );
    }

    if (response.statusCode == 403) {
      throw NewsApiException(
        code: code,
        statusCode: 403,
        message: serverMsg ?? 'You do not have permission to register media for this news story.',
        details: details,
      );
    }

    if (response.statusCode == 404) {
      throw NewsApiException(
        code: 'NEWS_NOT_FOUND',
        statusCode: 404,
        message: serverMsg ?? 'The news story was not found on the server.',
        details: details,
      );
    }

    if (response.statusCode == 422) {
      final errors = _extractFieldErrors(details.isNotEmpty ? details : bodyJson['errors']);
      throw NewsApiException(
        code: code,
        statusCode: 422,
        message: serverMsg ?? 'Media metadata validation failed.',
        fieldErrors: errors,
        details: details,
      );
    }

    if (response.statusCode >= 500) {
      throw NewsApiException(
        code: 'SERVER_ERROR',
        statusCode: response.statusCode,
        message: serverMsg ?? 'Server error (HTTP ${response.statusCode}). Please retry.',
        details: details,
      );
    }

    throw NewsApiException(
      code: code,
      statusCode: response.statusCode,
      message: serverMsg ?? 'Media registration failed (HTTP ${response.statusCode}).',
      details: details,
    );
  }

  /// Fetches the reporter's submitted news stories from `GET /api/v1/news`.
  Future<List<News>> getReporterNews({
    required String accessToken,
    String? statusFilter,
    int page = 1,
    int perPage = 25,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (statusFilter != null && statusFilter.isNotEmpty) {
      queryParams['status'] = statusFilter;
    }

    final baseUrl = _baseUrlResolver();
    final baseUri = Uri.parse('$baseUrl/news');
    final uri = baseUri.replace(queryParameters: queryParams);

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(_timeout);
    } on SocketException catch (e) {
      throw NewsApiException(
        code: 'NETWORK_ERROR',
        message: 'Unable to connect to server: ${e.message}',
      );
    } on TimeoutException {
      throw const NewsApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'Request timed out while fetching news. Please check network.',
      );
    } catch (e) {
      throw NewsApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Failed to fetch news: $e',
      );
    }

    Map<String, dynamic> bodyJson;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      bodyJson = decoded;
    } catch (_) {
      throw NewsApiException(
        code: 'INVALID_RESPONSE',
        statusCode: response.statusCode,
        message: 'Unexpected response from server (HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode == 200) {
      final data = bodyJson['data'];
      if (data is List) {
        return data.map((item) {
          final map = item as Map<String, dynamic>;
          return News(
            id: map['id']?.toString() ?? '',
            trackingCode: map['tracking_code'] as String? ?? 'REP-000',
            reporterId: map['reporter_id']?.toString() ?? 'user-001',
            reporterName: '',
            headline: map['headline'] as String? ?? '',
            category: map['category'] as String? ?? '',
            location: map['location'] as String? ?? '',
            incidentDetails: map['incident_details'] as String? ?? '',
            status: NewsStatus.fromString(map['status'] as String? ?? 'submitted'),
            isAiAssisted: map['is_ai_assisted'] as bool? ?? false,
            mediaRegistrationStatus: MediaRegistrationStatus.fromString(
              map['media_registration_status'] as String?,
            ),
            submittedAt: map['submitted_at'] != null
                ? DateTime.parse(map['submitted_at'] as String)
                : DateTime.now(),
          );
        }).toList();
      }
      return [];
    }

    _handleFetchError(response, bodyJson);
    return [];
  }

  /// Fetches details for a single news story from `GET /api/v1/news/{news}`.
  Future<News?> getNewsDetails({
    required String accessToken,
    required String newsId,
  }) async {
    final baseUrl = _baseUrlResolver();
    final uri = Uri.parse('$baseUrl/news/$newsId');

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(_timeout);
    } on SocketException catch (e) {
      throw NewsApiException(
        code: 'NETWORK_ERROR',
        message: 'Unable to connect to server: ${e.message}',
      );
    } on TimeoutException {
      throw const NewsApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'Request timed out while fetching news details.',
      );
    } catch (e) {
      throw NewsApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Failed to fetch news details: $e',
      );
    }

    Map<String, dynamic> bodyJson;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      bodyJson = decoded;
    } catch (_) {
      throw NewsApiException(
        code: 'INVALID_RESPONSE',
        statusCode: response.statusCode,
        message: 'Unexpected response from server (HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode == 200) {
      final data = bodyJson['data'];
      if (data is Map<String, dynamic>) {
        return News(
          id: data['id']?.toString() ?? newsId,
          trackingCode: data['tracking_code'] as String? ?? 'REP-000',
          reporterId: data['reporter_id']?.toString() ?? 'user-001',
          reporterName: '',
          headline: data['headline'] as String? ?? '',
          category: data['category'] as String? ?? '',
          location: data['location'] as String? ?? '',
          incidentDetails: data['incident_details'] as String? ?? '',
          status: NewsStatus.fromString(data['status'] as String? ?? 'submitted'),
          isAiAssisted: data['is_ai_assisted'] as bool? ?? false,
          mediaRegistrationStatus: MediaRegistrationStatus.fromString(
            data['media_registration_status'] as String?,
          ),
          submittedAt: data['submitted_at'] != null
              ? DateTime.parse(data['submitted_at'] as String)
              : DateTime.now(),
        );
      }
      return null;
    }

    if (response.statusCode == 404) return null;

    _handleFetchError(response, bodyJson);
    return null;
  }

  void _handleFetchError(http.Response response, Map<String, dynamic> bodyJson) {
    final errorObj = bodyJson['error'];
    final code = errorObj is Map<String, dynamic>
        ? (errorObj['code'] as String? ?? 'REQUEST_FAILED')
        : 'REQUEST_FAILED';
    final serverMsg = errorObj is Map<String, dynamic>
        ? (errorObj['message'] as String?)
        : null;

    if (response.statusCode == 401) {
      throw NewsApiException(
        code: 'UNAUTHENTICATED',
        statusCode: 401,
        message: serverMsg ?? 'Session expired. Please sign in again.',
      );
    }
    if (response.statusCode == 403) {
      throw NewsApiException(
        code: code,
        statusCode: 403,
        message: serverMsg ?? 'You do not have permission for this news story.',
      );
    }
    if (response.statusCode == 404) {
      throw NewsApiException(
        code: 'NEWS_NOT_FOUND',
        statusCode: 404,
        message: serverMsg ?? 'The news story was not found.',
      );
    }
    throw NewsApiException(
      code: code,
      statusCode: response.statusCode,
      message: serverMsg ?? 'Request failed (HTTP ${response.statusCode}).',
    );
  }

  static Map<String, List<String>> _extractFieldErrors(dynamic errorsJson) {
    if (errorsJson is! Map<String, dynamic>) return {};
    return errorsJson.map((key, value) {
      if (value is List) {
        return MapEntry(key, value.whereType<String>().toList());
      }
      if (value is String) {
        return MapEntry(key, [value]);
      }
      return MapEntry(key, <String>[]);
    });
  }
}
