import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_settings_input.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class ChannelsTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const ChannelsTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<ChannelsTab> {
  final Map<String, Map<String, TextEditingController>> _controllers = {};
  final Map<String, bool> _editingState = {};
  final Map<String, bool> _verifyingState = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    for (final channelControllers in _controllers.values) {
      for (final c in channelControllers.values) {
        c.dispose();
      }
    }
    _searchController.dispose();
    super.dispose();
  }

  TextEditingController _getController(
    String channelId,
    String fieldKey,
    String defaultValue,
  ) {
    if (!_controllers.containsKey(channelId)) {
      _controllers[channelId] = {};
    }
    return _controllers[channelId]!.putIfAbsent(
      fieldKey,
      () => TextEditingController(text: defaultValue),
    );
  }

  Future<void> _deleteChannelConfig(String channelId, String label) async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.api_keys.delete_key_title'.tr(
        namedArgs: {'label': label},
      ),
      content: 'settings.api_keys.delete_key_content'.tr(
        namedArgs: {'label': label},
      ),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      await ref.read(configProvider.notifier).updateChannels({
        channelId: {'enabled': false, 'settings': {}},
      });
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.channels.tg_disconnected_snack'.tr(),
        ); // Generic success snackbar
      }
    }
  }

  Future<void> _saveTelegramConfig() async {
    final token = _controllers['telegram']?['botToken']?.text.trim() ?? '';
    if (token.isEmpty) return;

    setState(() => _verifyingState['telegram'] = true);
    try {
      final validation = await ref
          .read(configProvider.notifier)
          .testKey('telegram', token);

      setState(() => _verifyingState['telegram'] = false);

      if (validation['status'] != 'ok') {
        if (mounted) {
          AppSnackBar.showError(
            context,
            'settings.channels.tg_failed_save'.tr(
              namedArgs: {'error': validation['message'] ?? 'Invalid token'},
            ),
          );
        }
        return;
      }

      final currentAllowFrom =
          _controllers['telegram']?['allowFrom']?.text.trim() ?? '';
      final List<String> allowFrom = currentAllowFrom.isNotEmpty
          ? currentAllowFrom
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : [];

      await ref.read(configProvider.notifier).updateChannels({
        'telegram': {
          'enabled': true,
          'dmPolicy': _selectedPolicies['telegram'] ?? 'open',
          'allowFrom': allowFrom,
          'settings': {'botToken': token},
        },
      });

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.channels.tg_connected_snack'.tr(),
        );
        setState(() {
          _editingState['telegram'] = false;
          _selectedPolicies.remove('telegram');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _verifyingState['telegram'] = false);
        AppSnackBar.showError(
          context,
          'settings.channels.tg_failed_save'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _saveGenericChannelConfig(String channelId) async {
    final channelControllers = _controllers[channelId] ?? {};
    final settings = <String, dynamic>{};
    String? allowFromRaw;

    for (final entry in channelControllers.entries) {
      if (entry.key == 'allowFrom') {
        allowFromRaw = entry.value.text.trim();
      } else {
        settings[entry.key] = entry.value.text.trim();
      }
    }

    // Check if at least one field is filled (excluding dm policy settings)
    final enabled = settings.values.any((v) => v.toString().isNotEmpty);
    final List<String> allowFrom =
        allowFromRaw != null && allowFromRaw.isNotEmpty
        ? allowFromRaw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : [];

    try {
      await ref.read(configProvider.notifier).updateChannels({
        channelId: {
          'enabled': enabled,
          'dmPolicy': _selectedPolicies[channelId] ?? 'pairing',
          'allowFrom': allowFrom,
          'settings': settings,
        },
      });

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'settings.channels.tg_connected_snack'.tr(),
        );
        setState(() {
          _editingState[channelId] = false;
          _selectedPolicies.remove(channelId);
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'settings.channels.tg_failed_save'.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  final Map<String, String> _selectedPolicies = {};

  String _getPolicyLabel(String policy) {
    switch (policy) {
      case 'pairing':
        return 'settings.channels.dm_policy_pairing'.tr();
      case 'allowlist':
        return 'settings.channels.dm_policy_allowlist'.tr();
      case 'open':
        return 'settings.channels.dm_policy_open'.tr();
      case 'disabled':
        return 'settings.channels.dm_policy_disabled'.tr();
      default:
        return policy;
    }
  }

  Widget _buildChannelCard(
    String channelId,
    String label,
    String iconPath,
    Map<String, dynamic> configChannels,
  ) {
    final channelConfig =
        configChannels[channelId] as Map<String, dynamic>? ?? {};
    final settings = channelConfig['settings'] as Map<String, dynamic>? ?? {};
    final isEnabled = channelConfig['enabled'] == true;
    final dmPolicyStr = channelConfig['dmPolicy'] as String? ?? 'pairing';
    final policy = _selectedPolicies[channelId] ?? dmPolicyStr;
    final isEditing = _editingState[channelId] ?? false;

    List<AppSettingsInputField> inputFields = [];
    VoidCallback onSave;

    if (channelId == 'googleChat') {
      inputFields = [
        if (policy != 'disabled')
          AppSettingsInputField(
            controller: _getController(
              channelId,
              'serviceAccountJsonPath',
              settings['serviceAccountJsonPath'] ?? '',
            ),
            label: 'settings.channels.gchat_sa_label',
            hint: 'settings.channels.gchat_sa_hint',
          ),
        if (policy != 'disabled')
          AppSettingsInputField(
            controller: _getController(
              channelId,
              'projectId',
              settings['projectId'] ?? '',
            ),
            label: 'settings.channels.gchat_project_label',
            hint: 'settings.channels.gchat_project_hint',
          ),
        if (policy != 'disabled')
          AppSettingsInputField(
            controller: _getController(
              channelId,
              'subscriptionId',
              settings['subscriptionId'] ?? '',
            ),
            label: 'settings.channels.gchat_sub_label',
            hint: 'settings.channels.gchat_sub_hint',
          ),
      ];
      onSave = () => _saveGenericChannelConfig(channelId);
    } else if (channelId == 'telegram') {
      if (policy != 'disabled') {
        inputFields = [
          AppSettingsInputField(
            controller: _getController(
              channelId,
              'botToken',
              settings['botToken'] ?? '',
            ),
            label: 'settings.channels.tg_token_label',
            hint: 'settings.channels.tg_token_hint',
          ),
        ];
      } else {
        inputFields = [];
      }
      onSave = _saveTelegramConfig;
    } else {
      if (policy != 'disabled') {
        inputFields = [
          AppSettingsInputField(
            controller: _getController(
              channelId,
              'token',
              settings['token'] ?? '',
            ),
            label: 'settings.channels.config_label',
            hint: 'settings.channels.config_hint',
          ),
        ];
      } else {
        inputFields = [];
      }
      onSave = () => _saveGenericChannelConfig(channelId);
    }

    // Add DM Authorization fields based on policy
    if (policy == 'pairing') {
      inputFields.add(
        AppSettingsInputField(
          controller: _getController(
            channelId,
            'pairingCode',
            settings['pairingCode'] ?? '',
          ),
          label: 'settings.channels.dm_policy_pairing_code',
          hint: 'settings.channels.dm_policy_pairing_code_hint',
        ),
      );
    } else if (policy == 'allowlist') {
      final currentAllowFrom =
          (channelConfig['allowFrom'] as List<dynamic>?)?.join(', ') ?? '';
      inputFields.add(
        AppSettingsInputField(
          controller: _getController(channelId, 'allowFrom', currentAllowFrom),
          label: 'settings.channels.dm_policy_allowlist_field',
          hint: 'settings.channels.dm_policy_allowlist_hint',
        ),
      );
    }

    final Widget leadingWidget = Image.asset(
      iconPath,
      width: AppConstants.integrationIconSize,
      height: AppConstants.integrationIconSize,
      errorBuilder: (context, error, stackTrace) {
        if (channelId == 'telegram') {
          return const Icon(
            Icons.telegram,
            color: AppColors.primary,
            size: AppConstants.integrationIconSize,
          );
        }
        return const Icon(
          Icons.chat_bubble_outline,
          color: AppColors.primary,
          size: AppConstants.integrationIconSize,
        );
      },
    );

    final policyDropdown = AppDropdownField<String>(
      label: 'settings.channels.dm_policy',
      hint: 'settings.channels.dm_policy_hint',
      value: policy,
      items: const ['pairing', 'allowlist', 'open', 'disabled'],
      displayValue: (p) => _getPolicyLabel(p),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedPolicies[channelId] = val);
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: AppSettingsInput(
        title: label,
        subtitle:
            '${'settings.channels.dm_policy'.tr()}: ${_getPolicyLabel(dmPolicyStr)}',
        translateSubtitle: false,
        leading: leadingWidget,
        isEditing: isEditing,
        isAlreadySet: isEnabled,
        isVerifying: _verifyingState[channelId] ?? false,
        inputs: inputFields,
        extraChild: policyDropdown,
        onEdit: () async {
          final token = await ref
              .read(configProvider.notifier)
              .getChannelToken(channelId);

          if (mounted) {
            setState(() {
              _editingState[channelId] = true;
              _selectedPolicies[channelId] = dmPolicyStr;

              // Sync controllers with current settings to ensure they reflect the stored state
              if (channelId == 'telegram') {
                final currentToken = token ?? settings['botToken'] ?? '';
                _getController(channelId, 'botToken', currentToken).text =
                    currentToken;
              } else if (channelId == 'googleChat') {
                for (final field in [
                  'serviceAccountJsonPath',
                  'projectId',
                  'subscriptionId',
                ]) {
                  _getController(channelId, field, settings[field] ?? '').text =
                      settings[field] ?? '';
                }
              } else {
                final currentToken = token ?? settings['token'] ?? '';
                _getController(channelId, 'token', currentToken).text =
                    currentToken;
              }

              if (dmPolicyStr == 'pairing') {
                _getController(
                  channelId,
                  'pairingCode',
                  settings['pairingCode'] ?? '',
                ).text = settings['pairingCode'] ?? '';
              } else if (dmPolicyStr == 'allowlist') {
                final currentAllowFrom =
                    (channelConfig['allowFrom'] as List<dynamic>?)?.join(
                      ', ',
                    ) ??
                    '';
                _getController(channelId, 'allowFrom', currentAllowFrom).text =
                    currentAllowFrom;
              }
            });
          }
        },
        onDelete: () => _deleteChannelConfig(channelId, label),
        onSave: onSave,
        onCancel: () => setState(() => _editingState[channelId] = false),
        addTooltip: 'settings.api_keys.add_tooltip',
        deleteTooltip: 'settings.api_keys.delete_tooltip',
        verifySaveTooltip: channelId == 'telegram'
            ? 'settings.api_keys.verify_save_tooltip'
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final channelsMap = config.channels as Map<String, dynamic>? ?? {};

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.settingsPagePadding,
              AppConstants.settingsTopPadding,
              AppConstants.settingsPagePadding,
              AppConstants.settingsPagePadding,
            ),
            children: [
              const AppSectionHeader(
                'settings.channels.section_title',
                large: true,
              ),
              TextField(
                controller: _searchController,
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                decoration:
                    AppInputDecoration.compact(
                      hint: 'settings.channels.search_placeholder'.tr(),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                size: 16,
                                color: AppColors.textDim,
                              ),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                    ).copyWith(
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.textDim,
                        size: 18,
                      ),
                      fillColor: AppColors.background,
                    ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Text(
                  'settings.channels.summary'.tr(),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: AppConstants.fontSizeBody,
                  ),
                ),
              ),
              ..._buildChannelSections(AppConstants.chatChannels, channelsMap),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  List<Widget> _buildChannelSections(
    List<Map<String, String>> channels,
    Map<String, dynamic> channelsMap,
  ) {
    final active = <Map<String, String>>[];
    final inactive = <Map<String, String>>[];

    for (final channelData in channels) {
      final id = channelData['id']!;

      if (_searchQuery.isNotEmpty) {
        final label = channelData['label']!.tr().toLowerCase();
        if (!label.contains(_searchQuery) && !id.contains(_searchQuery)) {
          continue;
        }
      }

      final channelConfig = channelsMap[id] as Map<String, dynamic>? ?? {};
      if (channelConfig['enabled'] == true) {
        active.add(channelData);
      } else {
        inactive.add(channelData);
      }
    }

    // Sort both by label
    active.sort((a, b) => a['label']!.tr().compareTo(b['label']!.tr()));
    inactive.sort((a, b) => a['label']!.tr().compareTo(b['label']!.tr()));

    final widgets = <Widget>[];

    if (active.isNotEmpty) {
      widgets.addAll(
        active.map(
          (channelData) => _buildChannelCard(
            channelData['id']!,
            channelData['label']!,
            AppConstants.getChannelIcon(channelData['id']!),
            channelsMap,
          ),
        ),
      );
    }

    if (inactive.isNotEmpty) {
      if (active.isNotEmpty) {
        widgets.add(const SizedBox(height: 32));
        widgets.add(
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppSectionLabel('settings.channels.other_channels'),
          ),
        );
      }
      widgets.addAll(
        inactive.map(
          (channelData) => _buildChannelCard(
            channelData['id']!,
            channelData['label']!,
            AppConstants.getChannelIcon(channelData['id']!),
            channelsMap,
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildNavButtons() {
    return AppSettingsNavBar(onBack: widget.onBack, onNext: widget.onNext);
  }
}
