import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logging/logging.dart';

import '../../providers/gateway_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/constants.dart';
import 'chat_screen.dart';
import 'setup_wizard_screen.dart';
import '../../providers/shell_provider.dart';
import '../../core/models/chat_session.dart';
import 'shell/sidebar_header.dart';
import 'shell/sidebar_footer.dart';
import 'shell/session_item.dart';
import 'shell/folder_item.dart';
import 'shell/settings/settings_dialog.dart';
import 'shell/widgets/new_chat_dialog.dart';
import 'shell/widgets/main_sidebar.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final _log = Logger('Ghost.ShellScreen');
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        ref.read(shellProvider.notifier).setSearchQuery(_searchController.text);
      }
    });

    _messageSub = ref.read(gatewayClientProvider).messages.listen((msg) {
      if (msg['method'] == 'gateway.error') {
        final errorMsg = msg['params']?['message'] ?? 'Unknown error';
        _showErrorOverlay(errorMsg);
      }
    });

    Future.microtask(() async {
      if (!mounted) return;
      final List<String> startupErrors = [];

      // 1. Connection errors from channels
      try {
        final result = await ref.read(gatewayClientProvider).call(
          'channels.getErrors',
          {'clear': false},
        );
        if (result != null && result['errors'] != null) {
          final errors = result['errors'] as List<dynamic>;
          for (final err in errors) {
            final msg = err['message'] as String? ?? 'Unknown error';
            startupErrors.add(msg);
          }
        }
      } catch (e) {
        // Ignore errors fetching channel errors
      }

      // 2. Ensure config is loaded from backend
      final config = ref.read(configProvider);
      if (config.isEmpty) {
        await ref.read(configProvider.notifier).refresh();
      }

      // Sync language from backend on startup
      if (mounted) {
        final currentConfig = ref.read(configProvider);
        final backendLang = currentConfig.user.language;
        if (backendLang != null && backendLang.isNotEmpty) {
          final locale = Locale(backendLang);
          if (context.locale != locale) {
            _log.info('Syncing locale from backend: $backendLang');
            context.setLocale(locale);
          }
        }
      }

      // 2b. Show setup wizard if no provider is configured
      if (mounted) {
        final currentConfig = ref.read(configProvider);
        if (currentConfig.agent.provider == null || currentConfig.agent.provider!.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const SetupWizardScreen(),
              ),
            );
          });
          return;
        }
      }

      // 3. Local startup checks (Auth & API Keys)
      startupErrors.addAll(_performStartupChecks());

      if (startupErrors.isNotEmpty) {
        _showErrorOverlay(startupErrors.join('\n\n'));
      }
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<String> _performStartupChecks() {
    final List<String> errors = [];
    final config = ref.read(configProvider);
    final googleUser = ref.read(authStateProvider);
    final vaultKeys = config.vaultKeys;

    // 1. Google Auth Check
    final hasWebId = vaultKeys.contains('google_client_id_web');
    final hasDesktopId = vaultKeys.contains('google_client_id_desktop');
    final isGoogleConfigured = kIsWeb ? hasWebId : hasDesktopId;

    if (isGoogleConfigured && googleUser == null) {
      errors.add('settings.integrations.google_startup_warning'.tr());
    }

    // 2. API Key Check
    final provider = config.agent.provider ?? 'openai';
    final keyName = provider == 'google' ? 'google_api_key' : '${provider}_api_key';

    if (!vaultKeys.contains(keyName) &&
        provider != 'ollama' &&
        provider != 'vllm' &&
        provider != 'litellm') {
      errors.add(
        'settings.api_keys.startup_warning'.tr(
          namedArgs: {'provider': provider},
        ),
      );
    }

    // 3. Telegram Token Check
    if (config.integrations['channels']?['telegram']?['enabled'] == true) {
      if (!vaultKeys.contains('telegram_bot_token')) {
        errors.add('settings.integrations.tg_startup_warning'.tr());
      }
    }

    return errors;
  }

  void _showErrorOverlay(String errorMessage) {
    if (!mounted) return;
    final lines = errorMessage.split('\n');
    final formattedMessage = lines.take(2).join('\n');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppConstants.iconColorError),
            const SizedBox(width: 8),
            Text('common.error'.tr()),
          ],
        ),
        content: Text(formattedMessage, style: const TextStyle(height: 1.4, fontSize: 14)),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  void _newChat() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const NewChatDialog(),
    );

    if (result != null) {
      final newId = const Uuid().v4();
      ref.read(shellProvider.notifier).setActiveSession(newId);

      final config = ref.read(configProvider);
      final identityName = config.identity.name;

      // Optimistically add to list
      ref.read(sessionsProvider.notifier).addPendingSession(ChatSession(
        id: newId,
        model: result['model'],
        provider: result['provider'],
        messageCount: 0,
        agentName: identityName,
        createdAt: DateTime.now(),
      ));

      ref.read(sessionsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shellState = ref.watch(shellProvider);
    final activeSessionId = shellState.activeSessionId;
    final collapsedFolders = shellState.collapsedFolders;
    final query = shellState.searchQuery.toLowerCase();

    ref.listen<String?>(authErrorProvider, (previous, next) {
      if (next != null) {
        _showErrorOverlay(next);
        Future.microtask(() => ref.read(authErrorProvider.notifier).setError(null));
      }
    });

    final sessions = ref.watch(sessionsProvider);
    final storedIds = sessions.map((s) => s.id).toSet();
    final showPendingNew = activeSessionId != null && !storedIds.contains(activeSessionId);

    final Map<String, List<ChatSession>> groupedSessions = {};
    final defaultAgentName = ref.watch(configProvider).identity.name;

    if (showPendingNew) {
      bool matches = true;
      if (query.isNotEmpty) {
        matches = 'new conversation'.contains(query) || (defaultAgentName.toLowerCase().contains(query));
      }
      if (matches) {
        groupedSessions[defaultAgentName] = [
          ChatSession(
            id: activeSessionId,
            messageCount: 0,
            agentName: defaultAgentName,
          )
        ];
      }
    }

    for (final s in sessions.reversed) {
      final agentName = s.agentName ?? defaultAgentName;
      final title = (s.title ?? '').toLowerCase();
      final agentLower = agentName.toLowerCase();

      if (query.isEmpty || title.contains(query) || agentLower.contains(query)) {
        groupedSessions.putIfAbsent(agentName, () => []).add(s);
      }
    }

    return Scaffold(
      body: Row(
        children: [
          MainSidebar(
            onNewChat: _newChat,
            searchController: _searchController,
            onShowSettings: () => _showSettings(context),
            onConfirmDeleteFolder: (agentName, sessions) => _confirmDeleteFolder(agentName, sessions, showPendingNew),
          ),
            Expanded(
              child: activeSessionId == null
                  ? _buildEmptyState()
                  : ChatScreen(key: ValueKey(activeSessionId), sessionId: activeSessionId),
            ),
          ],
        ),
      );
    }
  
    Future<void> _confirmDeleteFolder(String agentName, List<ChatSession> folderSessions, bool showPendingNew) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusDefault),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text('sidebar.delete_folder_title'.tr(namedArgs: {'name': agentName})),
          content: Text('sidebar.delete_folder_content'.tr(namedArgs: {'count': folderSessions.length.toString()})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr(), style: const TextStyle(color: AppColors.errorDark)),
            ),
          ],
        ),
      );
  
      if (confirmed == true) {
        final provider = ref.read(sessionsProvider.notifier);
        final shellNotifier = ref.read(shellProvider.notifier);
        final activeSessionId = ref.read(shellProvider).activeSessionId;
        for (final s in folderSessions) {
          final id = s.id;
          final isPending = showPendingNew && id == activeSessionId;
          if (!isPending) provider.deleteSession(id);
          if (activeSessionId == id) shellNotifier.setActiveSession(null);
        }
      }
    }
  
    Widget _buildEmptyState() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center, // Centered
            children: [
              Text(
                'chat.welcome_headline'.tr().toUpperCase(),
                style: const TextStyle(
                  fontSize: 56, // Editorial size
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.0,
                  height: 0.9,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'sidebar.start_conversation'.tr(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  color: AppColors.textDim,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _newChat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), // Brutalist corner
                ),
                child: Text(
                  'common.new_chat'.tr().toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SettingsDialog(),
    );
  }
}
