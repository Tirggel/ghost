import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/business_card.dart';
import '../../../widgets/app_snackbar.dart';

class IdentityTab extends ConsumerStatefulWidget {
  const IdentityTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<IdentityTab> createState() => _IdentityTabState();
}

class _IdentityTabState extends ConsumerState<IdentityTab> with SettingsSaveMixin {
  final _controllers = <String, TextEditingController>{};
  String? _selectedProvider;
  String? _selectedModel;
  String _selectedDesignSystem = '';
  List<String> _availableModels = [];
  final List<String> _mainAgentSkills = [];
  int _avatarNonce = 0;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  void _loadInitialValues() {
    final config = ref.read(configProvider);
    final identity = config.identity;
    final agent = config.agent;

    final nameText = identity.name;
    final creatureText = identity.creature ?? '';
    final vibeText = identity.vibe ?? '';
    final emojiText = identity.emoji ?? '🤖';
    final notesText = identity.notes ?? '';
    final avatarText = (identity.avatar?.startsWith('blob:') ?? false) ? '' : (identity.avatar ?? '');
    final designSystemText = agent.designSystem;

    if (_controllers.isEmpty) {
      _controllers['name'] = TextEditingController(text: nameText);
      _controllers['creature'] = TextEditingController(text: creatureText);
      _controllers['vibe'] = TextEditingController(text: vibeText);
      _controllers['emoji'] = TextEditingController(text: emojiText);
      _controllers['notes'] = TextEditingController(text: notesText);
      _controllers['avatar'] = TextEditingController(text: avatarText);
      _controllers['designSystem'] = TextEditingController(text: designSystemText);
    } else {
      _controllers['name']!.text = nameText;
      _controllers['creature']!.text = creatureText;
      _controllers['vibe']!.text = vibeText;
      _controllers['emoji']!.text = emojiText;
      _controllers['notes']!.text = notesText;
      _controllers['avatar']!.text = avatarText;
      _selectedDesignSystem = designSystemText;
    }

    _selectedProvider = agent.provider;
    _selectedModel = agent.model;
    _mainAgentSkills.clear();
    _mainAgentSkills.addAll(agent.skills);

    if (_selectedProvider != null) {
      _updateModels(_selectedProvider!);
    }
  }

  Future<void> _updateModels(String provider) async {
    final models = await ref
        .read(configProvider.notifier)
        .listModels(provider, null);
    if (mounted) {
      setState(() {
        _availableModels = models;
      });
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
      final avatar = _controllers['avatar']!.text;
      final identityConfig = {
        'name': _controllers['name']!.text,
        'creature': _controllers['creature']!.text,
        'vibe': _controllers['vibe']!.text,
        'emoji': _controllers['emoji']!.text,
        'notes': _controllers['notes']!.text,
        'avatar': avatar.startsWith('blob:') ? '' : avatar,
      };
      await ref.read(configProvider.notifier).updateIdentity(identityConfig);
      
      final agentData = <String, dynamic>{
        'skills': _mainAgentSkills,
        'designSystem': _selectedDesignSystem.trim(),
      };
      if (_selectedProvider != null) agentData['provider'] = _selectedProvider;
      if (_selectedModel != null) agentData['model'] = _selectedModel;
      
      await ref.read(configProvider.notifier).updateAgent(agentData);
      if (mounted) {
        setState(() => _isEditing = false);
      }
    }, 
    successMessage: 'settings.identity.saved'.tr(),
    silent: silent,
    );
  }

  @override
  Widget build(BuildContext context) {

    ref.listen(configProvider, (prev, next) {
      if (!isSaveLoading && prev != null && (prev.identity != next.identity || prev.agent != next.agent)) {
        // Force refresh all values on configuration change (e.g. after restore)
        _loadInitialValues();
      }
    });

    // Auto-save on main tab change
    ref.listen(shellProvider.select((s) => s.settingsTabIndex), (prev, next) {
      if (prev == 1 && next != 1 && _isEditing && !isSaveLoading) {
        _save(silent: true);
      }
    });

    // Auto-save on sub-tab change
    ref.listen(shellProvider.select((s) => s.settingsSubTabIndices[1] ?? 0), (prev, next) {
      if (prev == 0 && next != 0 && _isEditing && !isSaveLoading) {
        _save(silent: true);
      }
    });

    final config = ref.watch(configProvider);
    final availableProviders = config.getAvailableProviders(AppConstants.aiProviders);
    final availableProviderIds = availableProviders.map((p) => p['id']!).toList();
    
    final systemsAsync = ref.watch(designSystemsProvider);
    final systems = systemsAsync.value ?? [];
    
    final skillsAsync = ref.watch(skillsProvider);
    final skills = skillsAsync.value ?? [];


    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _isEditing && !isSaveLoading) {
          _save(silent: true);
        }
      },
      child: AppSettingsPage(
        onBack: widget.onBack,
        onNext: widget.onNext,
        onSave: _isEditing ? _save : null,
        isSaveLoading: isSaveLoading,
        topPadding: widget.topPadding,
        children: [
        const AppSectionHeader('settings.identity.section', large: true),
        Text(
          'settings.identity.desc'.tr(),
          style: const TextStyle(
            fontSize: AppConstants.fontSizeBody,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: AppConstants.settingsContentSpacing),
        BusinessCard(
          avatarBuilder: (context, isEditing) => ListenableBuilder(
            listenable: _controllers['avatar']!,
            builder: (context, _) => ListenableBuilder(
              listenable: _controllers['emoji']!,
              builder: (context, _) => GestureDetector(
                onTap: isEditing ? _onPickAvatar : null,
                child: Stack(
                  children: [
                    AppIdentityAvatar(
                      path: _controllers['avatar']!.text,
                      emoji: _controllers['emoji']!.text,
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
          ),
          fields: [
            BusinessCardField(
              label: 'settings.user.name_label',
              hint: 'settings.identity.name_hint',
              controller: _controllers['name']!,
            ),
            BusinessCardField(
              label: 'settings.identity.creature_label',
              hint: 'settings.identity.creature_hint',
              controller: _controllers['creature']!,
            ),
            BusinessCardField(
              label: 'settings.identity.vibe_label',
              hint: 'settings.identity.vibe_hint',
              controller: _controllers['vibe']!,
            ),
            BusinessCardField(
              label: 'settings.identity.emoji_label',
              hint: 'settings.identity.emoji_label',
              controller: _controllers['emoji']!,
              customEditWidget: _emojiInput(_controllers['emoji']!),
            ),
            BusinessCardField(
              label: 'settings.user.notes_label',
              hint: 'settings.identity.notes_hint',
              controller: _controllers['notes']!,
              maxLines: 3,
            ),
            BusinessCardField(
              label: 'settings.identity.provider_label',
              hint: 'settings.identity.choose_provider',
              controller: TextEditingController(text: _selectedProvider ?? ''),
              value: _selectedProvider != null
                  ? availableProviders.firstWhere(
                      (p) => p['id'] == _selectedProvider,
                      orElse: () => <String, String>{'id': _selectedProvider!, 'label': _selectedProvider!},
                    )['label']
                  : null,
              customEditWidget: AppUnifiedPicker<String>(
                value: _selectedProvider,
                label: 'settings.identity.provider_label',
                items: availableProviderIds,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedProvider = val;
                      _selectedModel = null;
                      _availableModels = [];
                    });
                    _updateModels(val);
                  }
                },
                displayValue: (v) {
                  final provider = availableProviders.firstWhere((p) => p['id'] == v, orElse: () => <String, String>{'id': v, 'label': v});
                  return provider['label']!;
                },
                itemPrefixIcon: (v) {
                  final provider = availableProviders.firstWhere((p) => p['id'] == v, orElse: () => <String, String>{'id': v, 'label': v});
                  final icon = provider['icon'];
                  if (icon != null) {
                    return Image.asset(
                      'assets/icons/llm/$icon',
                      width: 20,
                      height: 20,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.smart_toy, size: AppConstants.iconSizeSmall, color: AppColors.white),
                    );
                  }
                  return const Icon(Icons.smart_toy, size: AppConstants.iconSizeSmall, color: AppColors.white);
                },
              ),
            ),
            BusinessCardField(
              label: 'settings.identity.model_label',
              hint: 'settings.identity.choose_model',
              controller: TextEditingController(text: _selectedModel ?? ''),
              value: _selectedModel,
              customEditWidget: AppUnifiedPicker<String>(
                value: _selectedModel,
                items: _availableModels,
                label: 'settings.identity.model_label',
                hint: 'settings.identity.choose_model',
                displayValue: (v) => v,
                onChanged: (val) => setState(() => _selectedModel = val),
              ),
            ),
            BusinessCardField(
              label: 'settings.agents.design_system_label',
              hint: 'settings.agents.design_system_hint',
              controller: TextEditingController(),
              value: _selectedDesignSystem.isEmpty ? 'settings.agents.design_system_none'.tr() : _selectedDesignSystem,
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
              value: _mainAgentSkills.isEmpty ? 'settings.common.none'.tr() : _mainAgentSkills.map((sId) {
                final skill = skills.firstWhere((s) => s['slug'] == sId, orElse: () => {'name': sId});
                return skill['name'];
              }).join(', '),
              customEditWidget: AppUnifiedPicker<String>(
                values: _mainAgentSkills.toSet(),
                multiSelect: true,
                items: skills.map((s) => s['slug'] as String).toList(),
                label: 'settings.identity.skills_section',
                hint: 'settings.identity.skills_section',
                onMultiChanged: (vals) => setState(() {
                  _mainAgentSkills.clear();
                  _mainAgentSkills.addAll(vals);
                }),
                displayValue: (v) {
                  final skill = skills.firstWhere((s) => s['slug'] == v, orElse: () => {'name': v});
                  final emoji = skill['emoji'] != null ? '${skill['emoji']} ' : '';
                  return '$emoji${skill['name']}';
                },
              ),
            ),
          ],
          maxViewFields: 3,
          isEditing: _isEditing,
          onEditToggle: () => setState(() => _isEditing = !_isEditing),
          onSave: _save,
        ),
        const SizedBox(height: AppConstants.settingsSectionSpacing),
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
        final String? path = await configNotifier.uploadAvatar(
          name,
          bytes,
          wsUrl,
        );
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

  Widget _emojiInput(TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppFormLabel('settings.identity.emoji_label'),
          const SizedBox(height: 4),
          Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => showAppEmojiPicker(
                    context,
                    onSelected: (emoji) {
                      setState(() => controller.text = emoji);
                    },
                  ),
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(
                        AppConstants.buttonBorderRadius,
                      ),
                      color: AppColors.surface.withValues(alpha: 0.5),
                    ),
                    child: Text(
                      controller.text,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => showAppEmojiPicker(
                  context,
                  onSelected: (emoji) {
                    setState(() => controller.text = emoji);
                  },
                ),
                child: Text('settings.identity.pick_emoji'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }



}
