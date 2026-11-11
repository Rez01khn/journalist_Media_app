import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/errors/google_drive_exceptions.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/draft_sync_provider.dart';
import 'package:journalist_app_1/repositories/drive/google_drive_repository_impl.dart';
import 'package:journalist_app_1/repositories/google_drive_repository.dart';

/// State representation for Google Drive OAuth connection and file sync.
class GoogleDriveState {
  final bool isConnected;
  final String? accountEmail;
  final String? folderId;
  final String folderName;
  final bool isLoading;
  final String? errorMessage;
  final List<NewsMedia> files;

  const GoogleDriveState({
    this.isConnected = false,
    this.accountEmail,
    this.folderId,
    this.folderName = GoogleDriveRepositoryImpl.defaultFolderName,
    this.isLoading = false,
    this.errorMessage,
    this.files = const [],
  });

  GoogleDriveState copyWith({
    bool? isConnected,
    String? accountEmail,
    String? folderId,
    String? folderName,
    bool? isLoading,
    String? errorMessage,
    List<NewsMedia>? files,
    bool clearError = false,
  }) {
    return GoogleDriveState(
      isConnected: isConnected ?? this.isConnected,
      accountEmail: accountEmail ?? this.accountEmail,
      folderId: folderId ?? this.folderId,
      folderName: folderName ?? this.folderName,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      files: files ?? this.files,
    );
  }
}

/// Provider for the concrete GoogleDriveRepository.
/// Can be overridden in tests or for mock mode.
final googleDriveRepositoryProvider = Provider<GoogleDriveRepository>((ref) {
  return GoogleDriveRepositoryImpl();
});

/// Riverpod notifier managing Google Drive OAuth status, folder management, and file storage.
class GoogleDriveNotifier extends Notifier<GoogleDriveState> {
  @override
  GoogleDriveState build() {
    // Check initial connection asynchronously
    Future.microtask(() => checkConnectionStatus());
    return const GoogleDriveState();
  }

  GoogleDriveRepository get _repo => ref.read(googleDriveRepositoryProvider);

  /// Checks if an active Drive session is already authorized.
  Future<void> checkConnectionStatus() async {
    try {
      final email = await _repo.getCurrentAccountEmail();
      if (email != null && email.isNotEmpty) {
        final folderId = await _repo.getOrCreateAppFolder(
          folderName: state.folderName,
          reporterGoogleEmail: email,
        );
        state = state.copyWith(
          isConnected: true,
          accountEmail: email,
          folderId: folderId,
        );
        await refreshFiles();
        // Automatically sync pending drafts when Drive connection is verified
        Future.microtask(() {
          ref.read(draftSyncServiceProvider).syncAllPendingDrafts();
        });
      }
    } catch (_) {
      // Ignored during passive background check
    }
  }

  /// Connects reporter's personal Google Account with minimal `drive.file` scope.
  Future<bool> connectAccount({String? preferredEmail}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final emailHint = preferredEmail ?? '';
      await _repo.authorizeDrive(reporterGoogleEmail: emailHint);
      final realEmail = (await _repo.getCurrentAccountEmail()) ??
          (emailHint.isNotEmpty ? emailHint : 'connected@google.com');

      final folderId = await _repo.getOrCreateAppFolder(
        folderName: state.folderName,
        reporterGoogleEmail: realEmail,
      );

      final files = await _repo.listFiles(
        reporterGoogleEmail: realEmail,
        folderId: folderId,
      );

      state = state.copyWith(
        isConnected: true,
        accountEmail: realEmail,
        folderId: folderId,
        files: files,
        isLoading: false,
      );
      // Automatically sync pending drafts upon fresh connection
      Future.microtask(() {
        ref.read(draftSyncServiceProvider).syncAllPendingDrafts();
      });
      return true;
    } on GoogleDriveAuthCancelledException {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign-in was cancelled.',
      );
      return false;
    } on GoogleDriveOfflineException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
      return false;
    } on GoogleDriveException catch (e) {
      if (e.message.toLowerCase().contains('cancel')) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Sign-in was cancelled.',
        );
        return false;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      if (e.toString().toLowerCase().contains('cancel')) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Sign-in was cancelled.',
        );
        return false;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unexpected error: $e',
      );
      return false;
    }
  }

  /// Disconnects the connected Google account.
  Future<void> disconnectAccount() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.disconnectDrive();
      state = const GoogleDriveState();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to disconnect: $e',
      );
    }
  }

  /// Refreshes the list of files in the app's Drive folder.
  Future<void> refreshFiles() async {
    if (!state.isConnected || state.accountEmail == null) return;
    try {
      final files = await _repo.listFiles(
        reporterGoogleEmail: state.accountEmail!,
        folderId: state.folderId,
      );
      state = state.copyWith(files: files);
    } catch (_) {
      // Silently fail or keep existing list on refresh error
    }
  }

  /// Uploads a media asset to the reporter's Google Drive.
  Future<NewsMedia?> uploadMedia({
    required String localFilePath,
    required MediaType mediaType,
  }) async {
    if (!state.isConnected || state.accountEmail == null) {
      state = state.copyWith(
        errorMessage: 'Please connect your Google Drive account first.',
      );
      return null;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final uploaded = await _repo.uploadMediaToReporterDrive(
        localFilePath: localFilePath,
        mediaType: mediaType,
        reporterGoogleEmail: state.accountEmail!,
        targetFolderName: state.folderName,
      );

      final updatedFiles = [uploaded, ...state.files];
      state = state.copyWith(files: updatedFiles, isLoading: false);
      return uploaded;
    } on GoogleDriveException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Upload failed: $e',
      );
      return null;
    }
  }

  /// Uploads or updates a draft backup file to the reporter's Google Drive.
  Future<NewsMedia?> uploadDraft({
    required String localFilePath,
    required String draftId,
    String? existingDriveFileId,
  }) async {
    if (!state.isConnected || state.accountEmail == null) {
      state = state.copyWith(
        errorMessage: 'Please connect your Google Drive account first.',
      );
      return null;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final uploaded = await _repo.uploadDraftFile(
        localFilePath: localFilePath,
        draftId: draftId,
        reporterGoogleEmail: state.accountEmail!,
        targetFolderName: state.folderName,
        existingDriveFileId: existingDriveFileId,
      );

      // Update or add in files list without duplicates
      final existingIndex = state.files.indexWhere(
        (f) =>
            f.driveFileId == uploaded.driveFileId ||
            f.fileName == uploaded.fileName,
      );

      List<NewsMedia> updatedFiles;
      if (existingIndex != -1) {
        updatedFiles = List.of(state.files);
        updatedFiles[existingIndex] = uploaded;
      } else {
        updatedFiles = [uploaded, ...state.files];
      }

      state = state.copyWith(files: updatedFiles, isLoading: false);
      return uploaded;
    } on GoogleDriveException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Draft backup failed: $e',
      );
      return null;
    }
  }

  /// Deletes a file from the reporter's Google Drive.
  Future<bool> deleteMedia(String driveFileId) async {
    if (!state.isConnected || state.accountEmail == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _repo.deleteMediaFromReporterDrive(
        driveFileId: driveFileId,
        reporterGoogleEmail: state.accountEmail!,
      );

      if (success) {
        final updatedFiles =
            state.files.where((f) => f.driveFileId != driveFileId).toList();
        state = state.copyWith(files: updatedFiles, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
      return success;
    } on GoogleDriveException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Deletion failed: $e');
      return false;
    }
  }
}

/// Provider for Google Drive connection and storage state.
final googleDriveStateProvider =
    NotifierProvider<GoogleDriveNotifier, GoogleDriveState>(
  GoogleDriveNotifier.new,
);

