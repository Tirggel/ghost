import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

/// Desktop OAuth flow – opens the system browser, listens on localhost
/// for the redirect, exchanges code for tokens.
Future<Map<String, String?>?> performGoogleOAuth({
  required String clientId,
  required String clientSecret,
  required List<String> scopes,
}) async {
  final id = ClientId(clientId, clientSecret);

  final client = await clientViaUserConsent(id, scopes, (url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  });

  final token = client.credentials.accessToken.data;

  // Fetch user info from Google
  try {
    final response = await client.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      client.close();
      return {
        'accessToken': token,
        'email': json['email'] as String? ?? 'unknown',
        'displayName': (json['name'] as String?)?.isNotEmpty == true
            ? json['name'] as String?
            : (json['given_name'] != null || json['family_name'] != null)
                ? '${json['given_name'] ?? ''} ${json['family_name'] ?? ''}'.trim()
                : null,
        'photoUrl': json['picture'] as String?,
      };
    }
  } catch (_) {
    // Fall through
  }

  client.close();
  return {'accessToken': token, 'email': 'unknown'};
}
