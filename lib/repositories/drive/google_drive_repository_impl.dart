import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:journalist_app_1/core/constants/app_config.dart';
import 'package:journalist_app_1/core/errors/google_drive_exceptions.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/repositories/google_drive_repository.dart';

/// Concrete implementation of [GoogleDriveRepository] integrating with Google Drive v3 API.
///
/// Follows strict application architecture:
/// 1. Uses minimal scope `drive.file` so the app only accesses files it creates.
/// 2. Creates a dedicated folder ('Journalist App Dispatches') in reporter's Drive.
/// 3. Uploads original photos, audio notes, videos, thumbnails, and draft backups.
/// 4. Handles offline connectivity, token expiration, and user cancellation gracefully.
class GoogleDriveRepositoryImpl implements GoogleDriveRepository {
  static const String defaultFolderName = 'Journalist App Dispatches';
  static const List<String> scopes = [drive.DriveApi.driveFileScope, 'email'];

  final GoogleSignIn _googleSignIn;
  final http.Client? _customHttpClient;
  final drive.DriveApi? _customDriveApi;
  final String? _serverClientId;

  // Cached session state
  String? _cachedFolderId;
  String? _cachedFolderEmail;
  String? _cachedEmail;

  GoogleDriveRepositoryImpl({
    GoogleSignIn? googleSignIn,
    http.Client? customHttpClient,
    drive.DriveApi? customDriveApi,
    String? serverClientId,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _customHttpClient = customHttpClient,
       _customDriveApi = customDriveApi,
       _serverClientId =
           serverClientId ??
           (AppConfig.googleWebClientId.isNotEmpty
               ? AppConfig.googleWebClientId
               : null);

  @override
  Future<String?> getCurrentAccountEmail() async {
    if (_cachedEmail != null) return _cachedEmail;
    try {
      await _googleSignIn.initialize(
        clientId: _serverClientId,
        serverClientId: _serverClientId,
      );
      final account = await _googleSignIn.attemptLightweightAuthentication();
      if (account != null && account.email.isNotEmpty) {
        _cachedEmail = account.email;
        return _cachedEmail;
      }
      final headers = await _googleSignIn.authorizationClient
          .authorizationHeaders(scopes);
      if (headers != null && headers.isNotEmpty) {
        return _cachedEmail;
      }
    } catch (_) {
      // Not yet authenticated
    }
    return null;
  }

  @override
  Future<bool> isDriveAuthorized({required String reporterGoogleEmail}) async {
    try {
      final headers = await _googleSignIn.authorizationClient
          .authorizationHeaders(scopes);
      return headers != null &&
          headers.isNotEmpty &&
          (_cachedEmail == null || _cachedEmail == reporterGoogleEmail);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> authorizeDrive({required String reporterGoogleEmail}) async {
    try {
      await _googleSignIn.initialize(
        clientId: _serverClientId,
        serverClientId: _serverClientId,
      );
      final account = await _googleSignIn.authenticate(scopeHint: scopes);
      if (_cachedEmail != account.email) {
        _cachedFolderId = null;
        _cachedFolderEmail = null;
      }
      _cachedEmail = account.email;

      final headers = await account.authorizationClient.authorizationHeaders(
        scopes,
        promptIfNecessary: true,
      );

      if (headers == null || !headers.containsKey('Authorization')) {
        throw const GoogleDriveAuthCancelledException();
      }

      // Pre-warm / ensure app folder exists
      await getOrCreateAppFolder(
        folderName: defaultFolderName,
        reporterGoogleEmail: account.email,
      );

      return headers['Authorization'] ?? 'authorized';
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.toString().toLowerCase().contains('cancel')) {
        throw const GoogleDriveAuthCancelledException();
      }
      throw GoogleDriveException(
        'Google sign-in error: ${e.description ?? e.code.name}',
        e,
      );
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' ||
          e.code == 'canceled' ||
          e.toString().toLowerCase().contains('cancel')) {
        throw const GoogleDriveAuthCancelledException();
      }
      throw GoogleDriveException('Authentication error: ${e.message}', e);
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException(
        'Cannot connect to Google servers: ${e.message}',
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      if (e.toString().toLowerCase().contains('cancel')) {
        throw const GoogleDriveAuthCancelledException();
      }
      throw GoogleDriveException('Google Drive authorization failed: $e', e);
    }
  }

  @override
  Future<void> disconnectDrive() async {
    try {
      _cachedFolderId = null;
      _cachedFolderEmail = null;
      _cachedEmail = null;
      await _googleSignIn.signOut();
    } catch (e) {
      throw GoogleDriveException('Failed to disconnect Google Drive: $e', e);
    }
  }

  Future<drive.DriveApi> _getDriveApi() async {
    final customDrive = _customDriveApi;
    if (customDrive != null) {
      return customDrive;
    }

    try {
      final headers = await _googleSignIn.authorizationClient
          .authorizationHeaders(scopes, promptIfNecessary: true);

      if (headers == null || !headers.containsKey('Authorization')) {
        throw const GoogleDriveAuthExpiredException();
      }

      final client = _AuthenticatedHttpClient(
        _customHttpClient ?? http.Client(),
        headers,
      );
      return drive.DriveApi(client);
    } on SocketException {
      throw const GoogleDriveOfflineException();
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveAuthExpiredException('Session expired: $e');
    }
  }

  @override
  Future<String> getOrCreateAppFolder({
    required String folderName,
    required String reporterGoogleEmail,
  }) async {
    if (_cachedFolderId != null && _cachedFolderEmail == reporterGoogleEmail) {
      return _cachedFolderId!;
    }
    _cachedFolderId = null;
    _cachedFolderEmail = null;

    try {
      final driveApi = await _getDriveApi();

      // Search for existing folder with exact name
      final query =
          "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      final existingFiles = fileList.files;
      if (existingFiles != null && existingFiles.isNotEmpty) {
        _cachedFolderId = existingFiles.first.id!;
        _cachedFolderEmail = reporterGoogleEmail;
        return _cachedFolderId!;
      }

      // Create new folder
      final folderMetadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await driveApi.files.create(
        folderMetadata,
        $fields: 'id, name',
      );

      if (createdFolder.id == null) {
        throw const GoogleDriveFolderException(
          'Failed to retrieve created folder ID from Google Drive.',
        );
      }

      _cachedFolderId = createdFolder.id!;
      _cachedFolderEmail = reporterGoogleEmail;
      return _cachedFolderId!;
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException(
        'Network error during folder lookup: ${e.message}',
      );
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw GoogleDriveAuthExpiredException(
          'Drive authorization error: ${e.message}',
        );
      }
      throw GoogleDriveFolderException(
        'Google Drive API error: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveFolderException(
        'Failed to get or create app folder: $e',
        e,
      );
    }
  }

  @override
  Future<String> getOrCreateNewsFolder({
    required String newsTitle,
    required String reporterGoogleEmail,
    String? appFolderName,
    String? existingNewsFolderId,
  }) async {
    try {
      final driveApi = await _getDriveApi();
      final appFolderId = await getOrCreateAppFolder(
        folderName: appFolderName ?? defaultFolderName,
        reporterGoogleEmail: reporterGoogleEmail,
      );

      final cleanTitle = newsTitle
          .replaceAll(RegExp(r'[\r\n\t/\\]'), ' ')
          .trim();
      final safeFolderName = cleanTitle.isNotEmpty
          ? cleanTitle
          : 'Untitled News';
      final escapedName = safeFolderName.replaceAll("'", r"\'");

      // 1. If we already have a folder ID for this news draft, update/rename it in-place
      if (existingNewsFolderId != null && existingNewsFolderId.isNotEmpty) {
        try {
          final folderMeta = drive.File()..name = safeFolderName;
          final updated = await driveApi.files.update(
            folderMeta,
            existingNewsFolderId,
            $fields: 'id, name',
          );
          if (updated.id != null) {
            return updated.id!;
          }
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status != 404) {
            rethrow;
          }
          // Folder was deleted on Drive, fall back to search/create below
        }
      }

      // 2. Search inside the root App Folder for an existing folder with this News Title
      final query =
          "'$appFolderId' in parents and mimeType = 'application/vnd.google-apps.folder' and name = '$escapedName' and trashed = false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      final existingFolders = fileList.files;
      if (existingFolders != null && existingFolders.isNotEmpty) {
        return existingFolders.first.id!;
      }

      // 3. Create new News Title folder inside the App Folder
      final folderMetadata = drive.File()
        ..name = safeFolderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [appFolderId];

      final createdFolder = await driveApi.files.create(
        folderMetadata,
        $fields: 'id, name',
      );

      if (createdFolder.id == null) {
        throw const GoogleDriveFolderException(
          'Failed to retrieve created news folder ID from Google Drive.',
        );
      }

      return createdFolder.id!;
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException(
        'Network error during news folder lookup: ${e.message}',
      );
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw GoogleDriveAuthExpiredException(
          'Drive authorization error: ${e.message}',
        );
      }
      throw GoogleDriveFolderException(
        'Google Drive API error: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveFolderException(
        'Failed to get or create news folder: $e',
        e,
      );
    }
  }

  @override
  Future<List<NewsMedia>> listFiles({
    required String reporterGoogleEmail,
    String? folderId,
  }) async {
    try {
      final driveApi = await _getDriveApi();
      // Ensure root app folder exists
      final rootFolderId = await getOrCreateAppFolder(
        folderName: defaultFolderName,
        reporterGoogleEmail: reporterGoogleEmail,
      );

      // If listing for a specific news subfolder, filter by that parent;
      // otherwise list all non-folder files created by this app across all News folders.
      final bool isSpecificSubfolder =
          folderId != null && folderId.isNotEmpty && folderId != rootFolderId;
      final query = isSpecificSubfolder
          ? "'$folderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false"
          : "mimeType != 'application/vnd.google-apps.folder' and trashed = false";

      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields:
            'files(id, name, mimeType, size, webViewLink, webContentLink, createdTime)',
      );

      final items = fileList.files ?? [];
      return items.map((file) {
        final mime = file.mimeType ?? 'application/octet-stream';
        final mediaType = _detectMediaType(mime, file.name ?? '');

        return NewsMedia(
          id: 'media-${file.id}',
          fileName: file.name ?? 'untitled',
          driveFileId: file.id,
          driveWebViewLink: file.webViewLink,
          driveDownloadLink: file.webContentLink,
          mimeType: mime,
          fileSizeBytes: int.tryParse(file.size ?? ''),
          mediaType: mediaType,
          isUploadedToDrive: true,
          reporterGoogleAccountEmail: reporterGoogleEmail,
          createdAt: file.createdTime ?? DateTime.now(),
        );
      }).toList();
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException('Failed to list files: ${e.message}');
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw GoogleDriveAuthExpiredException(
          'Drive authorization error: ${e.message}',
        );
      }
      throw GoogleDriveException(
        'Drive API error while listing files: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException('Failed to list Google Drive files: $e', e);
    }
  }

  @override
  Future<NewsMedia> uploadMediaToReporterDrive({
    required String localFilePath,
    required MediaType mediaType,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw GoogleDriveUploadException(
        'Local media file does not exist at path: $localFilePath',
      );
    }

    try {
      final driveApi = await _getDriveApi();
      final folderId = (targetFolderId != null && targetFolderId.isNotEmpty)
          ? targetFolderId
          : await getOrCreateAppFolder(
              folderName: targetFolderName ?? defaultFolderName,
              reporterGoogleEmail: reporterGoogleEmail,
            );

      final fileName = file.uri.pathSegments.last;
      final mimeType = _resolveMimeType(mediaType, fileName);
      final fileSize = await file.length();

      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final uploadMedia = drive.Media(file.openRead(), fileSize);

      final uploaded = await driveApi.files.create(
        driveFile,
        uploadMedia: uploadMedia,
        $fields: 'id, name, mimeType, size, webViewLink, webContentLink',
      );

      if (uploaded.id == null) {
        throw const GoogleDriveUploadException(
          'Google Drive upload did not return an ID.',
        );
      }

      return NewsMedia(
        id: 'media-${uploaded.id}',
        fileName: uploaded.name ?? fileName,
        localFilePath: localFilePath,
        driveFileId: uploaded.id,
        driveWebViewLink: uploaded.webViewLink,
        driveDownloadLink: uploaded.webContentLink,
        mimeType: uploaded.mimeType ?? mimeType,
        fileSizeBytes: int.tryParse(uploaded.size ?? '') ?? fileSize,
        mediaType: mediaType,
        isUploadedToDrive: true,
        reporterGoogleAccountEmail: reporterGoogleEmail,
        createdAt: DateTime.now(),
      );
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException(
        'Upload failed due to offline connectivity: ${e.message}',
      );
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw GoogleDriveAuthExpiredException(
          'Drive upload failed: ${e.message}',
        );
      }
      throw GoogleDriveUploadException(
        'Google Drive API upload error: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveUploadException(
        'Failed to upload media to Google Drive: $e',
        e,
      );
    }
  }

  @override
  Future<NewsMedia> uploadDraftFile({
    required String localFilePath,
    required String draftId,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
    String? existingDriveFileId,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw GoogleDriveUploadException(
        'Local draft file does not exist at path: $localFilePath',
      );
    }

    try {
      final driveApi = await _getDriveApi();
      final folderId = (targetFolderId != null && targetFolderId.isNotEmpty)
          ? targetFolderId
          : await getOrCreateAppFolder(
              folderName: targetFolderName ?? defaultFolderName,
              reporterGoogleEmail: reporterGoogleEmail,
            );

      final fileName = file.uri.pathSegments.last;
      final fileSize = await file.length();
      final uploadMedia = drive.Media(file.openRead(), fileSize);

      drive.File? targetFile;

      // 1. If existingDriveFileId is provided, attempt updating that file directly
      //    and ensure it resides inside the target News folder (moving it if needed).
      if (existingDriveFileId != null && existingDriveFileId.isNotEmpty) {
        try {
          final existingMeta =
              await driveApi.files.get(
                    existingDriveFileId,
                    $fields: 'id, parents',
                  )
                  as drive.File;
          final currentParents = existingMeta.parents ?? [];
          final needsMove = !currentParents.contains(folderId);

          final fileMetadata = drive.File()..name = fileName;
          targetFile = await driveApi.files.update(
            fileMetadata,
            existingDriveFileId,
            addParents: needsMove ? folderId : null,
            removeParents: needsMove && currentParents.isNotEmpty
                ? currentParents.join(',')
                : null,
            uploadMedia: uploadMedia,
            $fields: 'id, name, mimeType, size, webViewLink, webContentLink',
          );
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status == 404) {
            // File was deleted on Google Drive, fallback to search/create
            targetFile = null;
          } else {
            rethrow;
          }
        }
      }

      // 2. If not updated by ID, query folder to check if draft file already exists
      if (targetFile == null) {
        final query =
            "'$folderId' in parents and name = '$fileName' and trashed = false";
        final searchResult = await driveApi.files.list(
          q: query,
          spaces: 'drive',
          $fields:
              'files(id, name, mimeType, size, webViewLink, webContentLink)',
        );

        if (searchResult.files != null && searchResult.files!.isNotEmpty) {
          final foundFile = searchResult.files!.first;
          final fileMetadata = drive.File()..name = fileName;
          targetFile = await driveApi.files.update(
            fileMetadata,
            foundFile.id!,
            uploadMedia: drive.Media(file.openRead(), fileSize),
            $fields: 'id, name, mimeType, size, webViewLink, webContentLink',
          );
        }
      }

      // 3. If still not found, create new draft file in app folder
      if (targetFile == null) {
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId];

        targetFile = await driveApi.files.create(
          driveFile,
          uploadMedia: drive.Media(file.openRead(), fileSize),
          $fields: 'id, name, mimeType, size, webViewLink, webContentLink',
        );
      }

      if (targetFile.id == null) {
        throw const GoogleDriveUploadException(
          'Google Drive upload did not return an ID.',
        );
      }

      return NewsMedia(
        id: 'draft-${targetFile.id}',
        fileName: targetFile.name ?? fileName,
        localFilePath: localFilePath,
        driveFileId: targetFile.id,
        driveWebViewLink: targetFile.webViewLink,
        driveDownloadLink: targetFile.webContentLink,
        mimeType: targetFile.mimeType ?? 'application/json',
        fileSizeBytes: int.tryParse(targetFile.size ?? '') ?? fileSize,
        mediaType: MediaType.document,
        isUploadedToDrive: true,
        reporterGoogleAccountEmail: reporterGoogleEmail,
        createdAt: DateTime.now(),
      );
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException(
        'Upload failed due to offline connectivity: ${e.message}',
      );
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw GoogleDriveAuthExpiredException(
          'Drive authorization error: ${e.message}',
        );
      }
      throw GoogleDriveUploadException(
        'Google Drive API upload error: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveUploadException(
        'Failed to upload draft file to Google Drive: $e',
        e,
      );
    }
  }

  @override
  Future<bool> deleteMediaFromReporterDrive({
    required String driveFileId,
    required String reporterGoogleEmail,
  }) async {
    try {
      final driveApi = await _getDriveApi();
      await driveApi.files.delete(driveFileId);
      return true;
    } on SocketException catch (e) {
      throw GoogleDriveOfflineException(
        'Cannot delete file while offline: ${e.message}',
      );
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        // File already deleted or does not exist
        return true;
      }
      if (e.status == 401 || e.status == 403) {
        throw GoogleDriveAuthExpiredException(
          'Authorization error: ${e.message}',
        );
      }
      throw GoogleDriveException('Drive deletion error: ${e.message}', e);
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to delete media from Google Drive: $e',
        e,
      );
    }
  }

  static String _resolveMimeType(MediaType mediaType, String fileName) {
    final lower = fileName.toLowerCase();
    switch (mediaType) {
      case MediaType.image:
        if (lower.endsWith('.png')) return 'image/png';
        if (lower.endsWith('.webp')) return 'image/webp';
        return 'image/jpeg';
      case MediaType.video:
        if (lower.endsWith('.mov')) return 'video/quicktime';
        return 'video/mp4';
      case MediaType.audio:
        if (lower.endsWith('.wav')) return 'audio/wav';
        if (lower.endsWith('.mp3')) return 'audio/mpeg';
        return 'audio/mp4';
      case MediaType.thumbnail:
        return 'image/jpeg';
      case MediaType.document:
        if (lower.endsWith('.json')) return 'application/json';
        return 'text/plain';
    }
  }

  static MediaType _detectMediaType(String mimeType, String fileName) {
    final lowerMime = mimeType.toLowerCase();
    final lowerName = fileName.toLowerCase();

    if (lowerMime.startsWith('image/') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png')) {
      if (lowerName.contains('thumb')) return MediaType.thumbnail;
      return MediaType.image;
    }
    if (lowerMime.startsWith('video/') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov')) {
      return MediaType.video;
    }
    if (lowerMime.startsWith('audio/') ||
        lowerName.endsWith('.m4a') ||
        lowerName.endsWith('.mp3') ||
        lowerName.endsWith('.wav')) {
      return MediaType.audio;
    }
    return MediaType.document;
  }
}

/// Private authenticated client that injects OAuth Bearer headers to each Google API request.
class _AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;

  _AuthenticatedHttpClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
