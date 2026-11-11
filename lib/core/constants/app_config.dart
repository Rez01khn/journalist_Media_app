/// Application-wide runtime configuration.
class AppConfig {
  /// Web OAuth 2.0 Client ID created in Google Cloud Console.
  ///
  /// Required by Google Sign-In on Android as `serverClientId` to exchange
  /// tokens with Google Drive scopes (`drive.file`).
  ///
  /// NOTE: Only Client ID is used. NEVER store or request the Client Secret.
  static const String googleWebClientId =
      '614059180899-mle0dj2b39qnv1i5a57rgti9gcao63se.apps.googleusercontent.com';
}

