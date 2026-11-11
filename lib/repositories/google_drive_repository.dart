import 'package:journalist_app_1/models/news_media.dart';

/// Abstract contract for reporter-owned Google Drive storage integration.
///
/// CRITICAL ARCHITECTURAL RULES:
/// 1. Original images, videos, voice recordings, text files, drafts, and thumbnails
///    belong in each reporter's personal Google Drive.
/// 2. Media is never uploaded directly to the web server or the existing Laravel database.
/// 3. Upload operations yield a [NewsMedia] record containing the Google Drive file ID
///    and web view link, which are then passed to the independent app API.
abstract class GoogleDriveRepository {
  /// Returns the email of the currently authenticated Google account, if any.
  Future<String?> getCurrentAccountEmail();

  /// Checks whether the reporter has granted Google Drive authorization.
  Future<bool> isDriveAuthorized({required String reporterGoogleEmail});

  /// Initiates OAuth2 authorization flow for the reporter's Google Drive.
  /// Requests minimal necessary scope: `drive.file`.
  Future<String> authorizeDrive({required String reporterGoogleEmail});

  /// Signs out and disconnects the reporter's Google Drive account from the app.
  Future<void> disconnectDrive();

  /// Gets or creates the app-specific root folder (e.g. 'Journalist App')
  /// in the reporter's personal Google Drive and returns its folder ID.
  Future<String> getOrCreateAppFolder({
    required String folderName,
    required String reporterGoogleEmail,
  });

  /// Gets, creates, or renames the news-specific subfolder inside the app's root folder:
  /// Sequence: `App Name` -> `News Title` -> all files of that news.
  /// If [existingNewsFolderId] is provided, updates its name if the headline changed.
  Future<String> getOrCreateNewsFolder({
    required String newsTitle,
    required String reporterGoogleEmail,
    String? appFolderName,
    String? existingNewsFolderId,
  });

  /// Lists files uploaded by this app in the reporter's Google Drive.
  Future<List<NewsMedia>> listFiles({
    required String reporterGoogleEmail,
    String? folderId,
  });

  /// Uploads a media asset (photo, audio dispatch, video, or thumbnail)
  /// directly into the reporter's personal Google Drive folder (or news subfolder).
  Future<NewsMedia> uploadMediaToReporterDrive({
    required String localFilePath,
    required MediaType mediaType,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
  });

  /// Uploads or updates a local draft backup file (e.g. JSON export) to the reporter's Drive.
  /// If [existingDriveFileId] is provided, updates the existing file without creating duplicates.
  Future<NewsMedia> uploadDraftFile({
    required String localFilePath,
    required String draftId,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
    String? existingDriveFileId,
  });

  /// Deletes a file from the reporter's Google Drive.
  Future<bool> deleteMediaFromReporterDrive({
    required String driveFileId,
    required String reporterGoogleEmail,
  });
}
