/// Stub – should never be reached at runtime.
Future<Map<String, String?>?> performGoogleOAuth({
  required String clientId,
  required String clientSecret,
  required List<String> scopes,
}) async {
  throw UnsupportedError('Google OAuth not supported on this platform');
}
