import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/google_oauth.dart';
import 'gateway_provider.dart';

const List<String> _kScopes = [
  'email',
  'https://www.googleapis.com/auth/calendar',
  'https://www.googleapis.com/auth/gmail.modify',
  'https://www.googleapis.com/auth/gmail.send',
  'https://www.googleapis.com/auth/drive',
];

/// Holds the signed-in user info.
class GoogleUser {

  GoogleUser({
    required this.email,
    this.displayName,
    this.photoUrl,
    required this.accessToken,
  });
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String accessToken;
}

final authStateProvider = NotifierProvider<AuthNotifier, GoogleUser?>(
  () => AuthNotifier(),
);

/// Whether Google Sign-In is available on this platform.
final googleSignInAvailableProvider =
    NotifierProvider<GoogleSignInAvailableNotifier, bool>(
      () => GoogleSignInAvailableNotifier(),
    );

/// Provides a way to surface authentication errors to the UI (e.g. token expired).
class AuthErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setError(String? error) => state = error;
}

final authErrorProvider = NotifierProvider<AuthErrorNotifier, String?>(
  () => AuthErrorNotifier(),
);

class GoogleSignInAvailableNotifier extends Notifier<bool> {
  @override
  bool build() => true; // Available on both web and desktop

  void setAvailable(bool value) => state = value;
}

class AuthNotifier extends Notifier<GoogleUser?> {
  @override
  GoogleUser? build() {
    final config = ref.watch(configProvider);
    final integrations = config.integrations;

    final email = integrations['googleEmail'] as String?;
    final vaultKeys =
        (config.vault['keys'] as List<dynamic>?)?.cast<String>() ?? [];

    if (email != null &&
        email.isNotEmpty &&
        vaultKeys.contains('google_access_token')) {
      // Validate token in the background
      Future.microtask(_verifyTokenAsync);
      return GoogleUser(
        email: email,
        displayName: integrations['googleDisplayName'] as String?,
        photoUrl: integrations['googlePhotoUrl'] as String?,
        accessToken: '', // Token is held securely on the backend
      );
    }

    return null;
  }

  Future<void> _verifyTokenAsync() async {
    try {
      final configNotifier = ref.read(configProvider.notifier);
      final result = await configNotifier.testKey('google_workspace', '');
      if (result['status'] != 'ok') {
        ref
            .read(authErrorProvider.notifier)
            .setError(
              'Your Google Workspace session has expired. Please sign in again via Settings > Integrations.',
            );
        await signOut();
      }
    } catch (_) {}
  }

  /// Sign in using OAuth 2.0.
  /// [clientId] and [clientSecret] are passed directly to avoid
  /// race conditions with async config saving.
  ///
  /// On Desktop: opens system browser → Google login → redirect to localhost.
  /// On Web: opens popup → Google login → token returned directly.
  Future<void> signIn({
    required String clientId,
    required String clientSecret,
  }) async {
    if (clientId.isEmpty) return;

    try {
      final result = await performGoogleOAuth(
        clientId: clientId,
        clientSecret: clientSecret,
        scopes: _kScopes,
      );

      if (result != null) {
        final token = result['accessToken'] ?? '';

        final user = GoogleUser(
          email: result['email'] ?? 'unknown',
          displayName: result['displayName'],
          photoUrl: result['photoUrl'],
          accessToken: token,
        );

        state = user;

        // Persist token to secure storage
        final configNotifier = ref.read(configProvider.notifier);
        await configNotifier.setKey('google_workspace', user.accessToken);

        // Persist user info to regular config
        await configNotifier.updateIntegrations({
          'googleEmail': user.email,
          'googleDisplayName': user.displayName,
          'googlePhotoUrl': user.photoUrl,
        });
      }
    } catch (e) {
      // Ignored
    }
  }

  Future<void> signOut() async {
    state = null;
    final configNotifier = ref.read(configProvider.notifier);
    await configNotifier.setKey('google_workspace', '');
    await configNotifier.updateIntegrations({
      'googleEmail': '',
      'googleDisplayName': '',
      'googlePhotoUrl': '',
    });
  }
}
