import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/searchable_model_picker.dart';
import '../../../widgets/business_card.dart';
import '../../../widgets/skills_selector_widget.dart';
import '../../../widgets/app_snackbar.dart';

class CustomAgentsTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const CustomAgentsTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<CustomAgentsTab> createState() => _CustomAgentsTabState();
}

class _CustomAgentsTabState extends ConsumerState<CustomAgentsTab> {
  final List<Map<String, dynamic>> _newAgents = [];

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final customAgents = config.customAgents;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppConstants.settingsPagePadding,
              AppConstants.settingsTopPadding,
              AppConstants.settingsPagePadding,
              AppConstants.settingsPagePadding,
            ),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const AppSectionHeader('settings.agents.section', large: true),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _newAgents.insert(0, {
                          'id': const Uuid().v4(),
                          'name': '',
                          'provider': null,
                          'model': null,
                          'avatar': '',
                          'cronSchedule': '',
                          'cronMessage': '',
                          'skills': <String>[],
                          'isNew': true,
                          'enabled': true,
                        });
                      });
                    },
                    icon: const Icon(Icons.add, size: AppConstants.settingsIconSize),
                    label: Text('settings.agents.add'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (customAgents.isEmpty && _newAgents.isEmpty)
                Text('settings.agents.empty'.tr(),
                    style: const TextStyle(color: AppColors.textDim))
              else ...[
                // New unsaved agents
                ..._newAgents.map((agent) => CustomAgentCard(
                      key: ValueKey(agent['id']),
                      agent: agent,
                      isNew: true,
                      onCancel: () {
                        setState(() {
                          _newAgents.remove(agent);
                        });
                      },
                      onSaved: () {
                        setState(() {
                          _newAgents.remove(agent);
                        });
                      },
                    )),
                // Existing agents
                ...customAgents.map((agent) {
                  final agentMap = agent as Map<String, dynamic>;
                  return CustomAgentCard(
                    key: ValueKey(agentMap['id'] ?? agentMap['name']),
                    agent: agentMap,
                  );
                }),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
        _buildNavButtons(context),
      ],
    );
  }

  Widget _buildNavButtons(BuildContext context) {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onNext: widget.onNext,
    );
  }
}

class CustomAgentCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> agent;
  final bool isNew;
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;

  const CustomAgentCard({
    super.key,
    required this.agent,
    this.isNew = false,
    this.onCancel,
    this.onSaved,
  });

  @override
  ConsumerState<CustomAgentCard> createState() => _CustomAgentCardState();
}

class _CustomAgentCardState extends ConsumerState<CustomAgentCard> with SettingsSaveMixin {
  final _controllers = <String, TextEditingController>{};
  String? _selectedProvider;
  String? _selectedModel;
  final List<String> _selectedSkills = [];
  List<String> _availableModels = [];
  bool _isLoadingModels = false;
  int _avatarNonce = 0;
  bool _enabled = true;
  bool _sendChatHistory = true;

  final Map<String, String> _cronPresets = {
    '': 'settings.agents.cron_none',
    '* * * * *': 'settings.agents.cron_every_minute',
    '*/5 * * * *': 'settings.agents.cron_every_5min',
    '*/10 * * * *': 'settings.agents.cron_every_10min',
    '*/15 * * * *': 'settings.agents.cron_every_15min',
    '*/30 * * * *': 'settings.agents.cron_every_30min',
    '0 * * * *': 'settings.agents.cron_hourly',
    '0 */2 * * *': 'settings.agents.cron_every_2h',
    '0 */6 * * *': 'settings.agents.cron_every_6h',
    '0 */12 * * *': 'settings.agents.cron_every_12h',
    '0 0 * * *': 'settings.agents.cron_daily_midnight',
    '0 9 * * *': 'settings.agents.cron_daily_9am',
    '0 0 * * 0': 'settings.agents.cron_weekly',
  };

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  void _loadInitialValues() {
    final agent = widget.agent;
    _controllers['name'] = TextEditingController(text: agent['name'] ?? '');
    _controllers['avatar'] = TextEditingController(text: agent['avatar'] ?? '');
    _controllers['cronSchedule'] =
        TextEditingController(text: agent['cronSchedule'] ?? '');
    _controllers['cronMessage'] =
        TextEditingController(text: agent['cronMessage'] ?? '');

    _selectedProvider = agent['provider'];
    _selectedModel = agent['model'];
    _enabled = agent['enabled'] ?? true;
    _sendChatHistory = agent['shouldSendChatHistory'] ?? true;
    if (_selectedSkills.isEmpty) {
        _selectedSkills.addAll((agent['skills'] as List<dynamic>?)?.cast<String>() ?? []);
    }

    if (_selectedProvider != null) {
      _fetchModels(_selectedProvider!);
    }
  }

  Future<void> _fetchModels(String provider) async {
    setState(() => _isLoadingModels = true);
    try {
      final models = await ref
          .read(configProvider.notifier)
          .listModels(provider, null);
      if (mounted) {
        setState(() {
          _availableModels = models;
          _isLoadingModels = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingModels = false);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await handleSave(() async {
      final newAgentData = {
        'id': widget.agent['id'] ?? const Uuid().v4(),
        'name': _controllers['name']!.text.trim(),
        'avatar': _controllers['avatar']!.text.trim(),
        'provider': _selectedProvider,
        'model': _selectedModel,
        'cronSchedule': _controllers['cronSchedule']!.text.trim(),
        'cronMessage': _controllers['cronMessage']!.text.trim(),
        'skills': _selectedSkills,
        'enabled': _enabled,
        'shouldSendChatHistory': _sendChatHistory,
      };

      if (widget.isNew) {
        await ref.read(configProvider.notifier).addCustomAgent(newAgentData);
        if (mounted) {
          widget.onSaved?.call();
        }
      } else {
        await ref.read(configProvider.notifier).updateCustomAgent(newAgentData);
      }
    }, successMessage: 'settings.agents.saved'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final vaultKeys = config.vaultKeys;
    final availableProviders = AppConstants.aiProviders.where((p) {
      final id = p['id']!;
      if (id == _selectedProvider) return true;
      final isLocal = id == 'ollama' ||
          id == 'ipex-llm' ||
          id == 'vllm' ||
          id == 'litellm' ||
          id == 'lmstudio';
      final storageKey = isLocal ? '${id}_base_url' : '${id}_api_key';

      final isAlreadySet = vaultKeys.contains(storageKey);
      final isDetected =
          config.detectedLocalProviders.any((dp) => dp['id'] == id);

      return isAlreadySet || isDetected;
    }).toList();

    final availableProviderIds = availableProviders.map((p) => p['id']!).toList();

    return BusinessCard(
      title: widget.isNew ? 'settings.agents.new_title' : 'settings.agents.edit_title',
      initialEdit: widget.isNew,
      isEnabled: _enabled,
      onToggleEnabled: (val) async {
          setState(() => _enabled = val);
          if (!widget.isNew) {
              await _save();
          }
      },
      onEditToggle: () {
          if (widget.isNew) {
              widget.onCancel?.call();
          }
      },
      onDelete: () async {
          if (widget.isNew) {
              widget.onCancel?.call();
          } else {
              await ref.read(configProvider.notifier).deleteCustomAgent(widget.agent['id'] ?? widget.agent['name'] ?? '');
          }
      },
      avatar: ListenableBuilder(
        listenable: _controllers['avatar']!,
        builder: (context, _) => GestureDetector(
          onTap: _onPickAvatar,
          child: Stack(
            children: [
              AppAssistantAvatar(
                path: _controllers['avatar']!.text,
                emoji: '🤖',
                radius: 46,
                iconSize: 32,
                extraVersion: _avatarNonce,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surface,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 14,
                    color: AppColors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      fields: [
        BusinessCardField(
          label: 'settings.agents.name_label',
          hint: 'settings.agents.name_hint',
          controller: _controllers['name']!,
        ),
        BusinessCardField(
          label: 'settings.agents.provider_label',
          hint: 'settings.identity.choose_provider',
          controller: TextEditingController(text: _selectedProvider ?? ''),
          value: _selectedProvider != null 
            ? AppConstants.aiProviders.firstWhere(
                (p) => p['id'] == _selectedProvider,
                orElse: () => {'label': _selectedProvider!},
              )['label']
            : null,
          customEditWidget: _buildProviderDropdown(availableProviders, availableProviderIds),
        ),
        BusinessCardField(
          label: 'settings.agents.model_label',
          hint: 'settings.agents.model_hint',
          controller: TextEditingController(text: _selectedModel ?? ''),
          value: _selectedModel,
          customEditWidget: SearchableModelPicker(
            selectedModel: _selectedModel,
            models: _availableModels,
            loading: _isLoadingModels,
            label: 'settings.agents.model_label',
            hint: 'settings.agents.model_hint',
            onSelected: (val) {
              setState(() => _selectedModel = val);
            },
          ),
        ),
        BusinessCardField(
          label: 'settings.agents.cron_label',
          hint: 'settings.agents.cron_hint',
          controller: _controllers['cronSchedule']!,
          value: _getCronDisplay(_controllers['cronSchedule']!.text),
          customEditWidget: _buildCronDropdown(),
        ),
        BusinessCardField(
          label: 'settings.agents.cron_message_label',
          hint: 'settings.agents.cron_message_hint',
          controller: _controllers['cronMessage']!,
          maxLines: 2,
        ),
        BusinessCardField(
          label: 'settings.agents.send_chat_history_label',
          hint: 'settings.agents.send_chat_history_hint',
          controller: TextEditingController(),
          value: (_sendChatHistory ? 'common.enabled' : 'common.disabled').tr(),
          customEditWidget: _buildChatHistoryToggle(),
        ),
      ],
      maxViewFields: 3,
      bottom: (context, isEditing) => _buildSkillsSection(isEditing),
      onSave: _save,
    );
  }

  String _getCronDisplay(String cron) {
    if (_cronPresets.containsKey(cron)) {
      return _cronPresets[cron]!.tr();
    }
    if (cron.isEmpty) return 'settings.agents.cron_none'.tr();
    return 'settings.agents.cron_custom'.tr(namedArgs: {'schedule': cron});
  }

  Widget _buildCronDropdown() {
    final currentCron = _controllers['cronSchedule']!.text;
    final isPreset = _cronPresets.containsKey(currentCron);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDropdownField<String>(
          value: isPreset ? currentCron : 'custom',
          label: 'settings.agents.cron_label',
          items: [..._cronPresets.keys, 'custom'],
          displayValue: (v) => v == 'custom' 
              ? 'settings.agents.cron_custom'.tr(namedArgs: {'schedule': ''}).split(' (').first
              : _cronPresets[v]!.tr(),
          onChanged: (val) {
            if (val != null && val != 'custom') {
              setState(() => _controllers['cronSchedule']!.text = val);
            }
          },
        ),
        if (!isPreset || currentCron == 'custom') ...[
          const SizedBox(height: 8),
          AppFormField.text(
            controller: _controllers['cronSchedule']!,
            label: '',
            hint: 'settings.agents.cron_hint',
          ),
        ],
      ],
    );
  }

  Widget _buildSkillsSection(bool isEditing) {
    return SkillsSelector(
      selectedSkills: _selectedSkills,
      isEditing: isEditing,
      onChanged: (next) {
        setState(() {
          _selectedSkills.clear();
          _selectedSkills.addAll(next);
        });
      },
    );
  }

  Widget _buildChatHistoryToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppFormLabel('settings.agents.send_chat_history_label'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'settings.agents.send_chat_history_hint'.tr(),
                  style: const TextStyle(
                    fontSize: AppConstants.fontSizeSmall,
                    color: AppColors.textDim,
                  ),
                ),
              ),
              Switch(
                value: _sendChatHistory,
                onChanged: (val) => setState(() => _sendChatHistory = val),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderDropdown(List<Map<String, String>> providers, List<String> ids) {
    return AppDropdownField<String>(
      value: _selectedProvider,
      label: 'settings.agents.provider_label',
      items: ids,
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedProvider = val;
            _selectedModel = null;
            _availableModels = [];
          });
          _fetchModels(val);
        }
      },
      displayValue: (v) => providers.firstWhere(
        (p) => p['id'] == v,
        orElse: () => {'label': v},
      )['label']!,
      itemBuilder: (id) => Row(
        children: [
          Image.asset(AppConstants.getProviderIcon(id), width: 18, height: 18),
          const SizedBox(width: 10),
          Text(
            providers.firstWhere(
              (p) => p['id'] == id,
              orElse: () => {'label': id},
            )['label']!,
            style: const TextStyle(fontSize: AppConstants.fontSizeBody),
          ),
        ],
      ),
    );
  }

  Future<void> _onPickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final name = result.files.single.name;
        final wsUrl = await ref.read(gatewayUrlProvider.future);

        final configNotifier = ref.read(configProvider.notifier);
        final String? path = await configNotifier.uploadAvatar(name, bytes, wsUrl);
        if (path != null) {
          setState(() {
            _controllers['avatar']!.text = path;
            _avatarNonce++;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}),
        );
      }
    }
  }
}
