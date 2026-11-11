/// Base exception for Google Drive operations.
class GoogleDriveException implements Exception {
  final String message;
  final dynamic cause;

  const GoogleDriveException(this.message, [this.cause]);

  @override
  String toString() =>
      'GoogleDriveException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}

/// Thrown when the user cancels the Google OAuth authentication dialog.
class GoogleDriveAuthCancelledException extends GoogleDriveException {
  const GoogleDriveAuthCancelledException([
    super.message = 'Google sign-in was cancelled by the user.',
  ]);
}

/// Thrown when Google OAuth authorization token has expired or is revoked.
class GoogleDriveAuthExpiredException extends GoogleDriveException {
  const GoogleDriveAuthExpiredException([
    super.message =
        'Google Drive authorization has expired. Please re-authenticate your Google account.',
  ]);
}

/// Thrown when network connectivity is offline or unavailable.
class GoogleDriveOfflineException extends GoogleDriveException {
  const GoogleDriveOfflineException([
    super.message =
        'No internet connection available. Media remains safely stored offline.',
  ]);
}

/// Thrown when file upload to Google Drive fails.
class GoogleDriveUploadException extends GoogleDriveException {
  const GoogleDriveUploadException(super.message, [super.cause]);
}

/// Thrown when folder lookup or creation in Google Drive fails.
class GoogleDriveFolderException extends GoogleDriveException {
  const GoogleDriveFolderException(super.message, [super.cause]);
}

