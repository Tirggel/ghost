import 'dart:convert';

import 'package:googleapis_auth/auth_browser.dart';
import 'package:http/http.dart' as http;

/// Web OAuth flow – uses Google Identity Services token model.
/// Opens a popup for Google consent, receives access token directly.
Future<Map<String, String?>?> performGoogleOAuth({
  required String clientId,
  required String clientSecret, // ignored on web
  required List<String> scopes,
}) async {
  final credentials = await requestAccessCredentials(
    clientId: clientId,
    scopes: scopes,
  );

  final token = credentials.accessToken.data;

  // Fetch user info
  try {
    final response = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'accessToken': token,
        'email': json['email'] as String? ?? 'unknown',
        'displayName': json['name'] as String?,
        'photoUrl': json['picture'] as String?,
      };
    }
  } catch (_) {
    // Fall through
  }

  return {'accessToken': token, 'email': 'unknown'};
}
