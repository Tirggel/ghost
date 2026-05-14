import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:cron/cron.dart' as cron_pkg;
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/business_card.dart';
import '../../../widgets/app_snackbar.dart';

class CustomAgentsTab extends ConsumerStatefulWidget {
  const CustomAgentsTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<CustomAgentsTab> createState() => _CustomAgentsTabState();
}

class _CustomAgentsTabState extends ConsumerState<CustomAgentsTab> {
  final List<Map<String, dynamic>> _newAgents = [];
  final Set<String> _editingIds = {};
  int _saveTrigger = 0;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final customAgents = config.customAgents;

    // Auto-save on main tab change
    ref.listen(shellProvider.select((s) => s.settingsTabIndex), (prev, next) {
      if (prev == 1 && next != 1 && _editingIds.isNotEmpty) {
        setState(() => _saveTrigger = _saveTrigger > 0 ? -(_saveTrigger + 1) : _saveTrigger - 1);
      }
    });

    // Auto-save on sub-tab change
    ref.listen(shellProvider.select((s) => s.settingsSubTabIndices[1] ?? 0), (prev, next) {
      if (prev == 1 && next != 1 && _editingIds.isNotEmpty) {
        setState(() => _saveTrigger = _saveTrigger > 0 ? -(_saveTrigger + 1) : _saveTrigger - 1);
      }
    });

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _editingIds.isNotEmpty) {
          setState(() => _saveTrigger = _saveTrigger > 0 ? -(_saveTrigger + 1) : _saveTrigger - 1);
        }
      },
      child: AppSettingsPage(
        onBack: widget.onBack,
        onNext: widget.onNext,
        topPadding: widget.topPadding,
        onSave: _editingIds.isNotEmpty ? () => setState(() => _saveTrigger = _saveTrigger < 0 ? -(_saveTrigger - 1) : _saveTrigger + 1) : null,
        children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const AppSectionHeader('settings.agents.section', large: true),
            AppActionButton(
              label: 'settings.agents.add',
              icon: Icons.add,
              isPrimary: true,
              onPressed: () {
                final id = const Uuid().v4();
                setState(() {
                  _newAgents.insert(0, {
                    'id': id,
                    'name': '',
                    'provider': null,
                    'model': null,
                    'avatar': '',
                    'cronSchedule': '',
                    'cronMessage': '',
                    'designSystem': '',
                    'skills': <String>[],
                    'isNew': true,
                    'enabled': true,
                  });
                  _editingIds.add(id);
                });
              },
            ),
          ],
        ),
        Text(
          'settings.agents.desc'.tr(),
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: AppConstants.fontSizeBody,
          ),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),
        if (customAgents.isEmpty && _newAgents.isEmpty)
          Text('settings.agents.empty'.tr(),
              style: const TextStyle(color: AppColors.textDim))
        else ...[
          // New unsaved agents
          ..._newAgents.map((agent) {
            final id = agent['id'] as String;
            return CustomAgentCard(
              key: ValueKey(id),
              agent: agent,
              isNew: true,
              isEditing: _editingIds.contains(id),
              saveTrigger: _saveTrigger,
              onEditToggle: () {
                setState(() {
                  if (_editingIds.contains(id)) {
                    _editingIds.remove(id);
                  } else {
                    _editingIds.add(id);
                  }
                });
              },
              onCancel: () {
                setState(() {
                  _newAgents.remove(agent);
                  _editingIds.remove(id);
                });
              },
              onSaved: () {
                setState(() {
                  _newAgents.remove(agent);
                  _editingIds.remove(id);
                });
              },
            );
          }),
          // Existing agents
          ...customAgents.map((agent) {
            return CustomAgentCard(
              key: ValueKey(agent.id),
              agent: agent,
              isEditing: _editingIds.contains(agent.id),
              saveTrigger: _saveTrigger,
              onEditToggle: () {
                setState(() {
                  if (_editingIds.contains(agent.id)) {
                    _editingIds.remove(agent.id);
                  } else {
                    _editingIds.add(agent.id);
                  }
                });
              },
              onSaved: () {
                setState(() {
                  _editingIds.remove(agent.id);
                });
              },
            );
          }),
        ],
        const SizedBox(height: 20),
      ],
    ),
  );
}
}

class CustomAgentCard extends ConsumerStatefulWidget {

  const CustomAgentCard({
    super.key,
    required this.agent,
    this.isNew = false,
    this.isEditing = false,
    this.onEditToggle,
    this.onCancel,
    this.onSaved,
    this.saveTrigger = 0,
  });
  final dynamic agent;
  final bool isNew;
  final bool isEditing;
  final VoidCallback? onEditToggle;
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;
  final int saveTrigger;

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
  String _selectedDesignSystem = '';
  int _avatarNonce = 0;
  bool _enabled = true;
  bool _sendChatHistory = true;
  int? _lastSaveTrigger;
  bool _customCronActive = false;

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
    '0 9 * * 1-5': 'settings.agents.cron_weekdays_9am',
    '0 18 * * *': 'settings.agents.cron_daily_6pm',
    '0 0 * * 0': 'settings.agents.cron_weekly',
    '0 0 1 * *': 'settings.agents.cron_monthly',
  };

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  void _loadInitialValues() {
    final agent = widget.agent;
    if (agent is CustomAgentConfig) {
      _controllers['name'] = TextEditingController(text: agent.name);
      _controllers['avatar'] = TextEditingController(text: agent.avatar ?? '');
      _controllers['cronSchedule'] =
          TextEditingController(text: agent.cronSchedule ?? '');
      _controllers['cronMessage'] =
          TextEditingController(text: agent.cronMessage);
      _selectedDesignSystem = agent.designSystem;

      _selectedProvider = agent.provider;
      _selectedModel = agent.model;
      _enabled = agent.enabled;
      _sendChatHistory = agent.shouldSendChatHistory;
      if (_selectedSkills.isEmpty) {
        _selectedSkills.addAll(agent.skills);
      }
    } else {
      final map = agent as Map<String, dynamic>;
      _controllers['name'] = TextEditingController(text: (map['name'] as String?) ?? '');
      _controllers['avatar'] = TextEditingController(text: (map['avatar'] as String?) ?? '');
      _controllers['cronSchedule'] =
          TextEditingController(text: (map['cronSchedule'] as String?) ?? '');
      _controllers['cronMessage'] =
          TextEditingController(text: (map['cronMessage'] as String?) ?? '');
      _selectedDesignSystem = (map['designSystem'] as String?) ?? '';

      _selectedProvider = map['provider'] as String?;
      _selectedModel = map['model'] as String?;
      _enabled = (map['enabled'] as bool?) ?? true;
      _sendChatHistory = (map['shouldSendChatHistory'] as bool?) ?? true;
      if (_selectedSkills.isEmpty) {
        _selectedSkills.addAll((map['skills'] as List<dynamic>?)?.cast<String>() ?? []);
      }
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

  Future<void> _save({bool silent = false}) async {
    await handleSave(() async {
      final agent = widget.agent;
      final id = (agent is CustomAgentConfig)
          ? agent.id
          : ((agent as Map<String, dynamic>)['id'] as String? ?? const Uuid().v4());

      final newAgentData = {
        'id': id,
        'name': _controllers['name']!.text.trim(),
        'avatar': _controllers['avatar']!.text.trim(),
        'provider': _selectedProvider,
        'model': _selectedModel,
        'cronSchedule': _controllers['cronSchedule']!.text.trim(),
        'cronMessage': _controllers['cronMessage']!.text.trim(),
        'designSystem': _selectedDesignSystem,
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
        if (mounted) {
          widget.onSaved?.call();
        }
      }
    }, 
    successMessage: 'settings.agents.saved'.tr(),
    silent: silent,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.saveTrigger != 0 && widget.saveTrigger != _lastSaveTrigger) {
      bool silent = widget.saveTrigger < 0;
      _lastSaveTrigger = widget.saveTrigger;
      if (widget.isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !isSaveLoading) {
            _save(silent: silent);
          }
        });
      }
    }

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
    
    final systemsAsync = ref.watch(designSystemsProvider);
    final systems = systemsAsync.value ?? [];
    
    final skillsAsync = ref.watch(skillsProvider);
    final skills = skillsAsync.value ?? [];

    return BusinessCard(
      initialEdit: widget.isNew,
      isEnabled: _enabled,
      onToggleEnabled: (val) async {
          setState(() => _enabled = val);
          if (!widget.isNew) {
              await _save();
          }
      },
      isEditing: widget.isEditing,
      onEditToggle: widget.isNew ? widget.onCancel : widget.onEditToggle,
      onDelete: () async {
          if (widget.isNew) {
              widget.onCancel?.call();
          } else {
              final agent = widget.agent;
              final id = (agent is CustomAgentConfig)
                  ? agent.id
                  : ((agent as Map<String, dynamic>)['id'] as String? ?? '');
              await ref.read(configProvider.notifier).deleteCustomAgent(id);
          }
      },
      avatarBuilder: (context, isEditing) => ListenableBuilder(
        listenable: _controllers['avatar']!,
        builder: (context, _) => GestureDetector(
          onTap: isEditing ? _onPickAvatar : null,
          child: Stack(
            children: [
              AppAssistantAvatar(
                path: _controllers['avatar']!.text,
                emoji: '🤖',
                radius: 46,
                iconSize: 32,
                extraVersion: _avatarNonce,
              ),
              if (isEditing)
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
          customEditWidget: AppUnifiedPicker<String>(
            value: _selectedProvider,
            label: 'settings.agents.provider_label',
            items: availableProviderIds,
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
            displayValue: (v) => availableProviders.firstWhere(
              (p) => p['id'] == v,
              orElse: () => {'label': v},
            )['label']!,
            itemPrefixIcon: (id) => Image.asset(AppConstants.getProviderIcon(id), width: 18, height: 18),
          ),
        ),
        BusinessCardField(
          label: 'settings.agents.model_label',
          hint: 'settings.agents.model_hint',
          controller: TextEditingController(text: _selectedModel ?? ''),
          value: _selectedModel,
          customEditWidget: AppUnifiedPicker<String>(
            value: _selectedModel,
            items: _availableModels,
            label: 'settings.agents.model_label',
            hint: 'settings.agents.model_hint',
            displayValue: (v) => v,
            onChanged: (val) => setState(() => _selectedModel = val),
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
          label: 'settings.agents.design_system_label',
          hint: 'settings.agents.design_system_hint',
          controller: TextEditingController(),
          value: _selectedDesignSystem.isEmpty 
              ? 'settings.agents.design_system_none'.tr() 
              : (() {
                  final sys = systems.firstWhere((s) => s['id'] == _selectedDesignSystem, orElse: () => {'name': _selectedDesignSystem});
                  return sys['name'] as String;
                })(),
          customEditWidget: AppUnifiedPicker<String>(
            value: _selectedDesignSystem.isEmpty ? null : _selectedDesignSystem,
            items: ['', ...systems.map((s) => s['id'] as String)],
            label: 'settings.agents.design_system_label',
            hint: 'settings.agents.design_system_hint',
            onChanged: (val) => setState(() => _selectedDesignSystem = val ?? ''),
            displayValue: (v) {
              if (v.isEmpty) return 'settings.agents.design_system_none'.tr();
              final sys = systems.firstWhere((s) => s['id'] == v, orElse: () => {'name': v});
              return sys['name'] as String;
            },
          ),
        ),
        BusinessCardField(
          label: 'settings.identity.skills_section',
          hint: 'settings.identity.skills_section',
          controller: TextEditingController(),
          value: _selectedSkills.isEmpty ? 'settings.common.none'.tr() : _selectedSkills.map((sId) {
            final skill = skills.firstWhere((s) => s['slug'] == sId, orElse: () => {'name': sId});
            return skill['name'];
          }).join(', '),
          customEditWidget: AppUnifiedPicker<String>(
            values: _selectedSkills.toSet(),
            multiSelect: true,
            items: skills.map((s) => s['slug'] as String).toList(),
            label: 'settings.identity.skills_section',
            hint: 'settings.identity.skills_section',
            onMultiChanged: (vals) => setState(() {
              _selectedSkills.clear();
              _selectedSkills.addAll(vals);
            }),
            displayValue: (v) {
              final skill = skills.firstWhere((s) => s['slug'] == v, orElse: () => {'name': v});
              final emoji = skill['emoji'] != null ? '${skill['emoji']} ' : '';
              return '$emoji${skill['name']}';
            },
          ),
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

  bool _isCronValid(String cron) {
    if (cron.isEmpty) return true;
    try {
      cron_pkg.Schedule.parse(cron);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _cronHint(String cron) {
    if (cron.isEmpty) return 'min hour day month weekday';
    if (!_isCronValid(cron)) return 'Ungültiges Format (z.B. */15 * * * *)';
    return 'Gültiges Cron-Format ✓';
  }

  Widget _buildCronDropdown() {
    final currentCron = _controllers['cronSchedule']!.text;
    final isPreset = _cronPresets.containsKey(currentCron);
    final showCustomField = _customCronActive || !isPreset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppUnifiedPicker<String>(
          value: showCustomField ? 'custom' : currentCron,
          label: 'settings.agents.cron_label',
          items: [..._cronPresets.keys, 'custom'],
          displayValue: (v) => v == 'custom' 
              ? 'settings.agents.cron_custom'.tr(namedArgs: {'schedule': ''}).split(' (').first
              : _cronPresets[v]!.tr(),
          onChanged: (val) {
            setState(() {
              if (val == 'custom') {
                _customCronActive = true;
              } else {
                _customCronActive = false;
                _controllers['cronSchedule']!.text = val!;
              }
            });
          },
        ),
        if (showCustomField) ...[
          const SizedBox(height: 8),
          AppFormField.text(
            controller: _controllers['cronSchedule']!,
            label: '',
            hint: 'settings.agents.cron_hint',
            onChanged: (val) {
              // If the user types a preset, we could potentially snap back, 
              // but it's better to stay in custom mode until they use the dropdown.
              setState(() {}); 
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _cronHint(currentCron),
              style: TextStyle(
                fontSize: AppConstants.fontSizeCaption,
                color: _isCronValid(currentCron) ? AppColors.textDim : AppColors.error,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ],
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
              AppSwitch(
                value: _sendChatHistory,
                onChanged: (val) => setState(() => _sendChatHistory = val),
              ),
            ],
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
