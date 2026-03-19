import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_logger/easy_logger.dart';
import 'core/gateway.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/gateway_provider.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/shell_screen.dart';

import 'package:easy_localization/easy_localization.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Only show warnings and errors from easy_localization
  EasyLocalization.logger.enableLevels = [
    LevelMessages.warning,
    LevelMessages.error,
  ];

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

    // Auto-connect if we have a token but are disconnected
    if (!isInitializing &&
        savedToken != null &&
        authStatus.value == ConnectionStatus.disconnected) {
      Future.microtask(() async {
        final client = ref.read(gatewayClientProvider);
        try {
          await client.connect();
          await client.login(savedToken);
        } catch (_) {}
      });
    }

    return MaterialApp(
      title: AppConstants.appName,
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
        // If an explicit error occurred, show the auth screen
        if (s == ConnectionStatus.error) {
          return const AuthScreen();
        }
        // If we have a token but aren't authenticated yet (e.g. connecting or disconnected),
        // show a loading state instead of flashing the login screen.
        return const LoadingScreen();
      },
      loading: () => const LoadingScreen(),
      error: (e, _) => const AuthScreen(), // Show auth if stream error
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
