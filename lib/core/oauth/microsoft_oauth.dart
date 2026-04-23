import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

String _generateCodeVerifier() {
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}

String _generateCodeChallenge(String verifier) {
  final bytes = utf8.encode(verifier);
  final digest = sha256.convert(bytes);
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// Validates a Microsoft Entra (Azure AD) App Registration Client ID.
/// Probes the /devicecode endpoint:
/// - Returns `false` for non-GUID input (error 50059) or invalid identifiers (error 700038).
/// - Returns `true` when the server issues a device_code (real app) or for
///   any other error that implies the app exists (e.g. Conditional Access 53003).
Future<bool> verifyMicrosoftClientId(String clientId) async {
  // Quick local format check: must be a valid UUID/GUID
  final uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  if (!uuidRegex.hasMatch(clientId)) return false;

  try {
    final response = await http
        .post(
          Uri.parse(
            'https://login.microsoftonline.com/common/oauth2/v2.0/devicecode',
          ),
          body: {
            'client_id': clientId,
            'scope': 'https://graph.microsoft.com/.default',
          },
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // Successful response: server issued a device code → app exists
    if (data.containsKey('device_code')) return true;

    final errorCodes =
        (data['error_codes'] as List<dynamic>?)?.cast<int>() ?? [];

    // 50059 = no tenant-identifying info → not a real Azure app Client ID
    // 700038 = not a valid application identifier
    if (errorCodes.contains(50059) || errorCodes.contains(700038)) {
      return false;
    }

    // Any other error (e.g. 53003 Conditional Access) implies the app does exist
    return true;
  } catch (_) {
    // Network error – give benefit of the doubt and allow the user to proceed
    return true;
  }
}

Future<Map<String, String>?> performMicrosoftOAuth({
  required String clientId,
  required List<String> scopes,
}) async {
  try {
    final redirectUri = 'http://localhost:8080';
    final tenant = 'consumers';
    final authorizeUrl =
        'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize';
    final tokenUrl =
        'https://login.microsoftonline.com/$tenant/oauth2/v2.0/token';

    // Generate PKCE code verifier and challenge
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    // Start local server to receive the redirect
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
    print('[MicrosoftOAuth] Local server started on port 8080');

    // Launch the browser
    final scopeString = ['offline_access', ...scopes].join(' ');
    final authUri = Uri.parse(authorizeUrl).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': scopeString,
      'response_mode': 'query',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    print('[MicrosoftOAuth] Requesting scopes: $scopeString');

    if (await canLaunchUrl(authUri)) {
      await launchUrl(authUri, mode: LaunchMode.externalApplication);
      print('[MicrosoftOAuth] Browser launched');
    } else {
      print('[MicrosoftOAuth] ERROR: Cannot launch browser URL');
      await server.close(force: true);
      return null;
    }

    // Wait for the redirect
    final request = await server.first;
    final code = request.uri.queryParameters['code'];
    final error = request.uri.queryParameters['error'];
    final errorDesc = request.uri.queryParameters['error_description'];

    if (error != null) {
      print('[MicrosoftOAuth] ERROR from Microsoft: $error — $errorDesc');
    }

    // Send a response to the browser
    final browserMsg = code != null
        ? 'Authentication successful!'
        : 'Authentication failed: ${error ?? "no code received"}';
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
          '<html><head><title>Authentication</title></head><body>'
          '<h1 style="text-align:center; margin-top:50px; font-family:sans-serif;">$browserMsg</h1>'
          '<p style="text-align:center; font-family:sans-serif;">You can close this window and return to Ghost.</p>'
          '</body></html>');
    await request.response.close();
    await server.close(force: true);

    if (code == null) {
      print('[MicrosoftOAuth] ERROR: No auth code received from redirect');
      return null;
    }
    print('[MicrosoftOAuth] Auth code received, exchanging for token...');

    // Exchange code for token
    final tokenResponse = await http.post(
      Uri.parse(tokenUrl),
      body: {
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    print('[MicrosoftOAuth] Token response status: ${tokenResponse.statusCode}');

    if (tokenResponse.statusCode != 200) {
      print('[MicrosoftOAuth] ERROR: Token exchange failed: ${tokenResponse.body}');
      return null;
    }

    final tokenData = jsonDecode(tokenResponse.body);
    final accessToken = tokenData['access_token'] as String?;

    if (accessToken == null) {
      print('[MicrosoftOAuth] ERROR: No access_token in response. Keys: ${tokenData.keys.toList()}');
      return null;
    }
    print('[MicrosoftOAuth] Access token received (${accessToken.length} chars)');

    // Extract user info from id_token JWT (most reliable for consumer accounts)
    String email = 'unknown@microsoft.com';
    String? displayName;

    final idToken = tokenData['id_token'] as String?;
    if (idToken != null) {
      try {
        final parts = idToken.split('.');
        if (parts.length == 3) {
          // Decode JWT payload (base64url, may need padding)
          String payload = parts[1];
          final remainder = payload.length % 4;
          if (remainder > 0) payload += '=' * (4 - remainder);
          final decoded = utf8.decode(base64Url.decode(payload));
          final claims = jsonDecode(decoded) as Map<String, dynamic>;
          print('[MicrosoftOAuth] JWT claims: preferred_username=${claims['preferred_username']}, name=${claims['name']}');

          final preferredUsername = claims['preferred_username'] as String?;
          final jwtName = claims['name'] as String?;
          if (preferredUsername != null && preferredUsername.isNotEmpty) {
            email = preferredUsername;
          }
          if (jwtName != null && jwtName.isNotEmpty) {
            displayName = jwtName;
          }
        }
      } catch (e) {
        print('[MicrosoftOAuth] WARNING: Failed to parse id_token: $e');
      }
    }

    // Fallback: try Graph /me if we still don't have good data
    if (email == 'unknown@microsoft.com' || displayName == null) {
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      print('[MicrosoftOAuth] Graph /me response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (email == 'unknown@microsoft.com') {
          email = data['mail'] ?? data['userPrincipalName'] ?? email;
        }
        displayName ??= data['displayName'];
        print('[MicrosoftOAuth] Graph /me fallback: $displayName <$email>');
      } else {
        print('[MicrosoftOAuth] WARNING: Graph /me failed: ${response.body}');
      }
    }

    print('[MicrosoftOAuth] Final user: $displayName <$email>');

    // Try to fetch profile photo from Graph API
    String? photoBase64;
    try {
      final photoResponse = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me/photo/\$value'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (photoResponse.statusCode == 200) {
        photoBase64 = base64Encode(photoResponse.bodyBytes);
        print('[MicrosoftOAuth] Profile photo fetched (${photoResponse.bodyBytes.length} bytes)');
      } else {
        print('[MicrosoftOAuth] No profile photo available (status: ${photoResponse.statusCode})');
      }
    } catch (e) {
      print('[MicrosoftOAuth] WARNING: Photo fetch failed: $e');
    }

    return {
      'accessToken': accessToken,
      'email': email,
      if (displayName != null) 'displayName': displayName,
      if (photoBase64 != null) 'photoBase64': photoBase64,
    };
  } catch (e, stackTrace) {
    print('[MicrosoftOAuth] EXCEPTION: $e');
    print('[MicrosoftOAuth] Stack: $stackTrace');
  }
  return null;
}
