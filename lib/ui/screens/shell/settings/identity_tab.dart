import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_avatar_picker.dart';
import '../../../widgets/searchable_model_picker.dart';
import '../../../widgets/business_card.dart';
import '../../../widgets/skills_selector_widget.dart';
import '../../../widgets/app_snackbar.dart';

class IdentityTab extends ConsumerStatefulWidget {
  const IdentityTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<IdentityTab> createState() => _IdentityTabState();
}

class _IdentityTabState extends ConsumerState<IdentityTab> with SettingsSaveMixin {
  final _controllers = <String, TextEditingController>{};
  String? _selectedProvider;
  String? _selectedModel;
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

    if (_controllers.isEmpty) {
      _controllers['name'] = TextEditingController(text: nameText);
      _controllers['creature'] = TextEditingController(text: creatureText);
      _controllers['vibe'] = TextEditingController(text: vibeText);
      _controllers['emoji'] = TextEditingController(text: emojiText);
      _controllers['notes'] = TextEditingController(text: notesText);
      _controllers['avatar'] = TextEditingController(text: avatarText);
    } else {
      _controllers['name']!.text = nameText;
      _controllers['creature']!.text = creatureText;
      _controllers['vibe']!.text = vibeText;
      _controllers['emoji']!.text = emojiText;
      _controllers['notes']!.text = notesText;
      _controllers['avatar']!.text = avatarText;
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
  Future<void> _save() async {
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
      };
      if (_selectedProvider != null) agentData['provider'] = _selectedProvider;
      if (_selectedModel != null) agentData['model'] = _selectedModel;
      
      await ref.read(configProvider.notifier).updateAgent(agentData);
      if (mounted) {
        setState(() => _isEditing = false);
      }
    }, successMessage: 'settings.identity.saved'.tr());
  }

  @override
  Widget build(BuildContext context) {

    ref.listen(configProvider, (prev, next) {
      if (!isSaveLoading && prev != null && (prev.identity != next.identity || prev.agent != next.agent)) {
        // Force refresh all values on configuration change (e.g. after restore)
        _loadInitialValues();
      }
    });

    final config = ref.watch(configProvider);
    final availableProviders = config.getAvailableProviders(AppConstants.aiProviders);
    final availableProviderIds = availableProviders.map((p) => p['id']!).toList();


    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      onSave: _isEditing ? _save : null,
      isSaveLoading: isSaveLoading,
      children: [
        BusinessCard(
          title: 'settings.identity.section',
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
              controller: TextEditingController(
                text: _selectedProvider ?? '',
              ),
              value: _selectedProvider != null
                  ? availableProviders.firstWhere(
                      (p) => p['id'] == _selectedProvider,
                      orElse: () => <String, String>{
                        'id': _selectedProvider!,
                        'label': _selectedProvider!,
                      },
                    )['label']
                  : null,
              customEditWidget: _buildProviderDropdown(
                availableProviders,
                availableProviderIds,
              ),
            ),
            BusinessCardField(
              label: 'settings.identity.model_label',
              hint: 'settings.identity.choose_model',
              controller: TextEditingController(
                text: _selectedModel ?? '',
              ),
              value: _selectedModel,
              customEditWidget: SearchableModelPicker(
                selectedModel: _selectedModel,
                models: _availableModels,
                label: 'settings.identity.model_label',
                hint: 'settings.identity.choose_model',
                onSelected: (val) {
                  setState(() => _selectedModel = val);
                },
              ),
            ),
          ],
          maxViewFields: 3,
          isEditing: _isEditing,
          onEditToggle: () => setState(() => _isEditing = !_isEditing),
          onSave: _save,
          bottom: (context, isEditing) => _buildSkillsSection(isEditing),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSkillsSection(bool isEditing) {
    return SkillsSelector(
      title: 'settings.identity.skills_section',
      selectedSkills: _mainAgentSkills,
      isEditing: isEditing,
      onChanged: (next) {
        setState(() {
          _mainAgentSkills.clear();
          _mainAgentSkills.addAll(next);
        });
      },
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

  Widget _buildProviderDropdown(
    List<Map<String, String>> availableProviders,
    List<String> availableProviderIds,
  ) {
    return AppDropdownField<String>(
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
        final provider = availableProviders.firstWhere(
          (p) => p['id'] == v,
          orElse: () => <String, String>{'id': v, 'label': v},
        );
        return provider['label']!;
      },
      itemBuilder: (v) {
        final provider = availableProviders.firstWhere(
          (p) => p['id'] == v,
          orElse: () => <String, String>{'id': v, 'label': v},
        );
        final icon = provider['icon'];
        return Row(
          children: [
            if (icon != null)
              Image.asset(
                'assets/icons/llm/$icon',
                width: 20,
                height: 20,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.smart_toy,
                  size: AppConstants.iconSizeSmall,
                  color: AppColors.white,
                ),
              )
            else
              const Icon(
                Icons.smart_toy,
                size: AppConstants.iconSizeSmall,
                color: AppColors.white,
              ),
            const SizedBox(width: 10),
            Text(provider['label']!),
          ],
        );
      },
    );
  }

}
