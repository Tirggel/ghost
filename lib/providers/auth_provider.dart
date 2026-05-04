import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/google_oauth.dart';
import '../core/oauth/microsoft_oauth.dart';
import 'gateway_provider.dart';

const List<String> _kScopes = [
  'openid',
  'profile',
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
            .setError('settings.integrations.google_session_expired');
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

        // Also update the main user profile if it's empty
        final currentConfig = ref.read(configProvider);
        final updates = <String, dynamic>{};
        if (currentConfig.user.name.isEmpty && user.displayName != null) {
          updates['name'] = user.displayName;
        }
        if (currentConfig.user.avatar == null && user.photoUrl != null) {
          updates['avatar'] = user.photoUrl;
        }
        if (updates.isNotEmpty) {
          await configNotifier.updateUser(updates);
        }
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

class MicrosoftUser {
  MicrosoftUser({
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

final microsoftAuthStateProvider =
    NotifierProvider<MicrosoftAuthNotifier, MicrosoftUser?>(
      () => MicrosoftAuthNotifier(),
    );

class MicrosoftAuthNotifier extends Notifier<MicrosoftUser?> {
  @override
  MicrosoftUser? build() {
    final config = ref.watch(configProvider);
    final integrations = config.integrations;

    final email = integrations['microsoftEmail'] as String?;
    final vaultKeys =
        (config.vault['keys'] as List<dynamic>?)?.cast<String>() ?? [];

    if (email != null &&
        email.isNotEmpty &&
        vaultKeys.contains('ms_graph_access_token')) {
      return MicrosoftUser(
        email: email,
        displayName: integrations['microsoftDisplayName'] as String?,
        photoUrl: integrations['microsoftPhotoUrl'] as String?,
        accessToken: '',
      );
    }
    return null;
  }

  Future<void> signIn({required String clientId}) async {
    if (clientId.isEmpty) return;

    try {
      print(
        '[MicrosoftAuth] Starting sign-in with clientId: ${clientId.substring(0, 8)}...',
      );
      final result = await performMicrosoftOAuth(
        clientId: clientId,
        scopes: [
          'openid',
          'profile',
          'email',
          'offline_access',
          'User.Read',
          'Mail.ReadWrite',
          'Mail.Send',
          'Files.ReadWrite.All',
          'Calendars.ReadWrite',
        ],
      );

      if (result != null) {
        final token = result['accessToken'] ?? '';
        print(
          '[MicrosoftAuth] OAuth successful, email: ${result['email']}, token length: ${token.length}',
        );

        final configNotifier = ref.read(configProvider.notifier);

        // Upload profile photo if available
        String? photoPath;
        final photoBase64 = result['photoBase64'];
        if (photoBase64 != null) {
          try {
            final photoBytes = base64Decode(photoBase64);
            final wsUrl =
                ref.read(gatewayUrlProvider).value ?? 'ws://127.0.0.1:18789';
            photoPath = await configNotifier.uploadAvatar(
              'ms_profile_photo.jpg',
              photoBytes,
              wsUrl,
            );
            print('[MicrosoftAuth] Profile photo uploaded: $photoPath');
          } catch (e) {
            print('[MicrosoftAuth] WARNING: Photo upload failed: $e');
          }
        }

        final user = MicrosoftUser(
          email: result['email'] ?? 'unknown',
          displayName: result['displayName'],
          photoUrl: photoPath,
          accessToken: token,
        );

        state = user;

        await configNotifier.setKey('ms_workspace', user.accessToken);
        print('[MicrosoftAuth] Token saved to vault');

        await configNotifier.updateIntegrations({
          'microsoftEmail': user.email,
          'microsoftDisplayName': user.displayName,
          'microsoftPhotoUrl': user.photoUrl ?? '',
        });
        print('[MicrosoftAuth] Integrations updated with user info');
      } else {
        print('[MicrosoftAuth] OAuth returned null — sign-in failed');
      }
    } catch (e, stackTrace) {
      print('[MicrosoftAuth] EXCEPTION in signIn: $e');
      print('[MicrosoftAuth] Stack: $stackTrace');
    }
  }

  Future<void> signOut() async {
    state = null;
    final configNotifier = ref.read(configProvider.notifier);
    await configNotifier.setKey('ms_workspace', '');
    await configNotifier.updateIntegrations({
      'microsoftEmail': '',
      'microsoftDisplayName': '',
      'microsoftPhotoUrl': '',
    });
  }
}
