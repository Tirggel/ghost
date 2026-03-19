import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_settings_input.dart';

class ChannelsTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const ChannelsTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<ChannelsTab> {
  final Map<String, TextEditingController> _controllers = {};
  bool _editingTelegram = false;
  bool _verifyingTelegram = false;
  bool _editingGChat = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getController(String key, String defaultValue) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: defaultValue),
    );
  }


  Future<void> _saveTelegramConfig() async {
    final token = _controllers['tg_token']?.text.trim() ?? '';
    if (token.isEmpty) return;

    setState(() => _verifyingTelegram = true);
    try {
      final validation = await ref
          .read(configProvider.notifier)
          .testKey('telegram', token);

      setState(() => _verifyingTelegram = false);

      if (validation['status'] != 'ok') {
        if (mounted) {
          _showSnackBar(
            'settings.channels.tg_failed_save'.tr(
              namedArgs: {'error': validation['message'] ?? 'Invalid token'},
            ),
            isError: true,
          );
        }
        return;
      }

      await ref.read(configProvider.notifier).updateChannels({
        'telegram': {
          'enabled': true,
          'dmPolicy': 'open',
          'settings': {'botToken': token},
        },
      });
      if (mounted) {
        _showSnackBar('settings.channels.tg_connected_snack'.tr());
        _controllers['tg_token']?.clear();
        setState(() => _editingTelegram = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _verifyingTelegram = false);
        _showSnackBar(
          'settings.channels.tg_failed_save'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    }
  }

  Future<void> _deleteTelegramConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'settings.api_keys.delete_key_title'.tr(
            namedArgs: {'label': 'Telegram'},
          ),
        ),
        content: Text(
          'settings.api_keys.delete_key_content'.tr(
            namedArgs: {'label': 'Telegram'},
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textDim,
              side: const BorderSide(color: AppColors.border),
            ),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'common.delete'.tr(),
              style: const TextStyle(color: AppColors.errorDark),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(configProvider.notifier).updateChannels({
        'telegram': {'enabled': false, 'settings': {}},
      });
      if (mounted) {
        _showSnackBar('settings.channels.tg_disconnected_snack'.tr());
      }
    }
  }

  Future<void> _deleteGChatConfig() async {
    final label = 'settings.channels.gchat_section'.tr();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('settings.api_keys.delete_key_title'.tr(namedArgs: {'label': label})),
        content: Text('settings.api_keys.delete_key_content'.tr(namedArgs: {'label': label})),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr(), style: const TextStyle(color: AppColors.errorDark)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(configProvider.notifier).updateChannels({
        'googleChat': {'enabled': false, 'settings': {}},
      });
      if (mounted) {
        _showSnackBar('settings.channels.tg_disconnected_snack'.tr()); // Reuse snackbar if appropriate or add new key
      }
    }
  }

  Future<void> _saveGChatConfig() async {
    final settings = {
      'serviceAccountJsonPath': _controllers['gchat_sa']?.text.trim() ?? '',
      'projectId': _controllers['gchat_project']?.text.trim() ?? '',
      'subscriptionId': _controllers['gchat_sub']?.text.trim() ?? '',
    };
    final enabled = settings.values.every((v) => v.isNotEmpty);
    await ref.read(configProvider.notifier).updateChannels({
      'googleChat': {'enabled': enabled, 'settings': settings},
    });
    setState(() => _editingGChat = false);
    if (mounted) _showSnackBar('settings.channels.tg_connected_snack'.tr()); // Reuse snackbar
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.errorDark : AppColors.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final channels = config.channels;
    final googleChatSettings = channels['googleChat']?['settings'] as Map<String, dynamic>? ?? {};

    final saController = _getController('gchat_sa', googleChatSettings['serviceAccountJsonPath'] ?? '');
    final projectIdController = _getController('gchat_project', googleChatSettings['projectId'] ?? '');
    final subIdController = _getController('gchat_sub', googleChatSettings['subscriptionId'] ?? '');
    final tgTokenController = _getController('tg_token', '');

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const AppSectionHeader('settings.channels.gchat_section', large: true),
              Text('settings.channels.gchat_desc'.tr(), style: const TextStyle(color: AppColors.textDim, fontSize: AppConstants.fontSizeBody)),
              AppSettingsInput(
                title: 'settings.channels.gchat_section',
                leading: Image.asset(AppConstants.getProviderIcon('google'), width: 20, height: 20),
                isEditing: _editingGChat,
                isAlreadySet: channels['googleChat']?['enabled'] == true,
                inputs: [
                  AppSettingsInputField(
                    controller: saController,
                    label: 'settings.channels.gchat_sa_label',
                    hint: 'settings.channels.gchat_sa_hint',
                  ),
                  AppSettingsInputField(
                    controller: projectIdController,
                    label: 'settings.channels.gchat_project_label',
                    hint: 'settings.channels.gchat_project_hint',
                  ),
                  AppSettingsInputField(
                    controller: subIdController,
                    label: 'settings.channels.gchat_sub_label',
                    hint: 'settings.channels.gchat_sub_hint',
                  ),
                ],
                onEdit: () => setState(() => _editingGChat = true),
                onDelete: _deleteGChatConfig,
                onSave: _saveGChatConfig,
                onCancel: () => setState(() => _editingGChat = false),
                addTooltip: 'settings.api_keys.add_tooltip',
                deleteTooltip: 'settings.api_keys.delete_tooltip',
              ),
              const SizedBox(height: 32),
              const AppSectionHeader('settings.channels.tg_section', large: true),
              Text('settings.channels.tg_desc'.tr(), style: const TextStyle(color: AppColors.textDim, fontSize: AppConstants.fontSizeBody)),
              const SizedBox(height: 16),
              AppSettingsInput(
                title: 'settings.channels.tg_token_label',
                leading: const Icon(Icons.telegram, color: AppColors.primary),
                controller: tgTokenController,
                isEditing: _editingTelegram,
                isAlreadySet: channels['telegram']?['enabled'] == true,
                isVerifying: _verifyingTelegram,
                obscureText: true,
                hint: 'settings.channels.tg_token_hint',
                onEdit: () => setState(() => _editingTelegram = true),
                onDelete: _deleteTelegramConfig,
                onSave: _saveTelegramConfig,
                onCancel: () => setState(() => _editingTelegram = false),
                addTooltip: 'settings.api_keys.add_tooltip',
                deleteTooltip: 'settings.api_keys.delete_tooltip',
                verifySaveTooltip: 'settings.api_keys.verify_save_tooltip',
              ),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onNext: widget.onNext,
    );
  }
}
