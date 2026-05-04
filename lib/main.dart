import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_logger/easy_logger.dart';
import 'core/gateway.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/gateway_provider.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/shell_screen.dart';
import 'core/internal_gateway.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await windowManager.ensureInitialized();

  windowManager.waitUntilReadyToShow(null, () async {
    await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  // Only show warnings and errors from easy_localization
  EasyLocalization.logger.enableLevels = [
    LevelMessages.warning,
    LevelMessages.error,
  ];

  // Initialize and start Internal Gateway if enabled
  final gatewayManager = InternalGatewayManager();
  await gatewayManager.initialize();
  if (await gatewayManager.isEnabled()) {
    try {
      await gatewayManager.start();
    } catch (_) {
      // Background start failure shouldn't crash the UI
    }
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('de')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const ProviderScope(child: MainApp()),
    ),
  );
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(connectionStatusProvider);
    final savedTokenAsync = ref.watch(authTokenProvider);
    final gatewayUrlAsync = ref.watch(gatewayUrlProvider);

    final savedToken = savedTokenAsync.value;
    final isInitializing =
        savedTokenAsync.isLoading || gatewayUrlAsync.isLoading;

    // Auto-connect if we have a token but are disconnected or in error state.
    if (!isInitializing &&
        savedToken != null &&
        (authStatus.value == ConnectionStatus.disconnected ||
            authStatus.value == ConnectionStatus.error)) {
      Future.microtask(() async {
        // If it was an error, wait a bit before retrying to avoid spamming
        if (authStatus.value == ConnectionStatus.error) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }

        final client = ref.read(gatewayClientProvider);
        try {
          await client.connect();
          final success = await client.login(savedToken);
          if (!success) {
            // Auto-login failed (e.g., token was reset) — clear it and trigger re-discovery
            await ref.read(authTokenProvider.notifier).logout();
            ref.invalidate(authTokenProvider);
          }
        } catch (_) {}
      });
    }

    // (The restoring state is now handled by modal dialogs that require the user to exit the app.)

    return MaterialApp(
      title: AppConstants.appName,
      navigatorKey: AppConstants.navigatorKey,
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppConstants.snackbarKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        return Scaffold(
          body: child!,
          resizeToAvoidBottomInset: false, // Inner screens handle this
        );
      },
      home: isInitializing
          ? const LoadingScreen()
          : _buildHome(authStatus, savedToken, ref),
    );
  }

  Widget _buildHome(
    AsyncValue<ConnectionStatus> status,
    String? token,
    WidgetRef ref,
  ) {
    if (token == null) return const AuthScreen();

    // If we have a token, we are trying to auto-connect.
    // Show loading while we are not yet authenticated.
    return status.when(
      data: (s) {
        if (s == ConnectionStatus.authenticated) {
          return const ShellScreen();
        }

        // If we've been trying to connect for a while and failed, show the error with an escape hatch
        if (s == ConnectionStatus.error) {
          return LoadingScreen(
            status: s,
            onAction: () => ref.read(authTokenProvider.notifier).logout(),
            actionLabel: 'auth.back_to_login'.tr(),
          );
        }

        // If we have a token but aren't authenticated yet (e.g. connecting, disconnected),
        // show a loading state instead of flashing the login screen.
        return LoadingScreen(status: s);
      },
      loading: () => const LoadingScreen(),
      error: (e, _) => LoadingScreen(
        error: e.toString(),
        onAction: () => ref.read(authTokenProvider.notifier).logout(),
        actionLabel: 'auth.back_to_login'.tr(),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    this.status,
    this.error,
    this.onAction,
    this.actionLabel,
    this.message,
    this.showLoader = true,
  });

  final ConnectionStatus? status;
  final String? error;
  final VoidCallback? onAction;
  final String? actionLabel;
  final String? message;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showLoader) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 32),
            ],
            if (message != null)
              Text(
                message!,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: AppConstants.fontSizeTitle,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            if (status != null && message == null)
              Text(
                '${'common.status'.tr()}: ${status!.name}',
                style: const TextStyle(color: AppColors.textDim),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            if (onAction != null) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel ?? 'common.cancel'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
