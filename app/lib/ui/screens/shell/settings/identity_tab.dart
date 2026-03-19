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

class IdentityTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const IdentityTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<IdentityTab> createState() => _IdentityTabState();
}

class _IdentityTabState extends ConsumerState<IdentityTab> {
  final _controllers = <String, TextEditingController>{};
  String? _selectedProvider;
  String? _selectedModel;
  List<String> _availableModels = [];
  final List<String> _mainAgentSkills = [];
  final Set<String> _activeLocalProviders = {};
  int _avatarNonce = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
    _checkLocalProviders();
  }

  void _loadInitialValues() {
    final config = ref.read(configProvider);
    final identity = config.identity;
    final agent = config.agent;

    _controllers['name'] = TextEditingController(text: identity.name);
    _controllers['creature'] = TextEditingController(text: identity.creature);
    _controllers['vibe'] = TextEditingController(text: identity.vibe);
    _controllers['emoji'] = TextEditingController(text: identity.emoji);
    _controllers['notes'] = TextEditingController(text: identity.notes);
    _controllers['avatar'] = TextEditingController(
      text: (identity.avatar?.startsWith('blob:') ?? false)
          ? ''
          : (identity.avatar ?? ''),
    );

    _selectedProvider = agent.provider;
    _selectedModel = agent.model;
    _mainAgentSkills.addAll(agent.skills);

    if (_selectedProvider != null) {
      _updateModels(_selectedProvider!);
    }
  }

  Future<void> _checkLocalProviders() async {
    for (final p in AppConstants.aiProviders) {
      if (p['id'] == 'ollama' || p['id'] == 'vllm' || p['id'] == 'litellm') {
        try {
          final models = await ref
              .read(configProvider.notifier)
              .listModels(p['id']!, null);
          if (models.isNotEmpty) {
            if (mounted) {
              setState(() {
                _activeLocalProviders.add(p['id']!);
              });
            }
          }
        } catch (_) {}
      }
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
    await ref.read(configProvider.notifier).updateAgentSkills(_mainAgentSkills);

    if (_selectedProvider != null && _selectedModel != null) {
      await ref.read(configProvider.notifier).updateAgent({
        'provider': _selectedProvider,
        'model': _selectedModel,
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('settings.identity.saved'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (prev, next) {
      final identity = next.identity;
      final agent = next.agent;
      if (identity.name.isNotEmpty && _controllers['name']!.text.isEmpty) {
        _controllers['name']!.text = identity.name;
        _controllers['creature']!.text = identity.creature ?? '';
        _controllers['vibe']!.text = identity.vibe ?? '';
        _controllers['emoji']!.text = identity.emoji ?? '🤖';
        _controllers['notes']!.text = identity.notes ?? '';
        _controllers['avatar']!.text = identity.avatar ?? '';
      }
      if (_selectedProvider == null && agent.provider != null) {
        setState(() {
          _selectedProvider = agent.provider;
          _selectedModel = agent.model;
        });
        if (_selectedProvider != null) {
          _updateModels(_selectedProvider!);
        }
      }
    });

    final config = ref.watch(configProvider);
    final vaultKeys = config.vault['keys'] as List<dynamic>? ?? [];

    final availableProviders = AppConstants.aiProviders.where((p) {
      final id = p['id']!;
      if (id == 'ollama' || id == 'vllm' || id == 'litellm') {
        return _activeLocalProviders.contains(id);
      }
      final keyName = id == 'google' ? 'google_api_key' : '${id}_api_key';
      return vaultKeys.contains(keyName);
    }).toList();

    final availableProviderIds = availableProviders
        .map((p) => p['id']!)
        .toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BusinessCard(
                title: 'settings.identity.section',
                avatar: ListenableBuilder(
                  listenable: _controllers['avatar']!,
                  builder: (context, _) => ListenableBuilder(
                    listenable: _controllers['emoji']!,
                    builder: (context, _) => GestureDetector(
                      onTap: _onPickAvatar,
                      child: Stack(
                        children: [
                          AppIdentityAvatar(
                            path: _controllers['avatar']!.text,
                            emoji: _controllers['emoji']!.text,
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
                onSave: _save,
                bottom: (context, isEditing) => _buildSkillsSection(isEditing),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        _buildNavButtons(),
      ],
    );
  }

  Widget _buildSkillsSection(bool isEditing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader('settings.identity.skills_section'),
        ref.watch(skillsProvider).when(
          data: (skills) {
            if (skills.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'settings.skills.no_skills'.tr(),
                  style: const TextStyle(color: AppColors.textDim),
                ),
              );
            }
            return Column(
              children: skills.map((skill) {
                final slug = skill['slug'] as String;
                final isEnabled = _mainAgentSkills.contains(slug);
                return CheckboxListTile(
                  title: Text(skill['name'] ?? slug),
                  contentPadding: EdgeInsets.zero,
                  subtitle: Text(
                    skill['description'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: isEnabled,
                  activeColor: AppColors.primary,
                  onChanged: isEditing 
                    ? (val) {
                        setState(() {
                          if (val == true) {
                            _mainAgentSkills.add(slug);
                          } else {
                            _mainAgentSkills.remove(slug);
                          }
                        });
                      }
                    : null,
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Text('settings.skills.error_loading_generic'.tr()),
        ),
      ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}),
            ),
            backgroundColor: AppColors.errorDark,
          ),
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
              Container(
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

  Widget _buildNavButtons() {
    return AppSettingsNavBar(
      onBack: widget.onBack,
      onSave: _save,
      onNext: widget.onNext,
    );
  }
}
