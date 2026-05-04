import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/setup_wizard_provider.dart';
import '../widgets/setup_wizard/wizard_step_language.dart';
import '../widgets/setup_wizard/wizard_step_restore.dart';
import '../widgets/setup_wizard/wizard_step_provider.dart';
import '../widgets/setup_wizard/wizard_step_user.dart';
import '../widgets/setup_wizard/wizard_step_identity.dart';
import '../widgets/setup_wizard/wizard_step_workspace.dart';
import '../widgets/app_styles.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/setup_wizard/wizard_step_indicator.dart';

// ---------------------------------------------------------------------------
// SetupWizardScreen — shown on first run / after reset when no provider set
// ---------------------------------------------------------------------------

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  static const int _totalSteps = 6;

  // Controllers are still needed for AppFormField/TextField
  final _apiKeyCtrl = TextEditingController();
  final _userNameCtrl = TextEditingController();
  final _userCallSignCtrl = TextEditingController();
  final _userNotesCtrl = TextEditingController();
  final _userAvatarCtrl = TextEditingController();
  final _identNameCtrl = TextEditingController();
  final _identCreatureCtrl = TextEditingController();
  final _identVibeCtrl = TextEditingController();
  final _identEmojiCtrl = TextEditingController(text: '🤖');
  final _identNotesCtrl = TextEditingController();
  final _identAvatarCtrl = TextEditingController();
  final _workspaceCtrl = TextEditingController();

  // Cache-busting nonces per upload key
  final Map<String, int> _avatarNonces = {};

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyCtrl.dispose();
    _userNameCtrl.dispose();
    _userCallSignCtrl.dispose();
    _userNotesCtrl.dispose();
    _userAvatarCtrl.dispose();
    _identNameCtrl.dispose();
    _identCreatureCtrl.dispose();
    _identVibeCtrl.dispose();
    _identEmojiCtrl.dispose();
    _identNotesCtrl.dispose();
    _identAvatarCtrl.dispose();
    _workspaceCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Pre-populate fields from existing vault data
    Future.microtask(() => _loadInitialData());
  }

  Future<void> _loadInitialData() async {
    final config = ref.read(configProvider);
    if (config.isEmpty) {
      await ref.read(configProvider.notifier).refresh();
    }
    final updatedConfig = ref.read(configProvider);
    if (!mounted || updatedConfig.isEmpty) return;

    final notifier = ref.read(setupWizardProvider.notifier);
    final user = updatedConfig.user;
    final agent = updatedConfig.agent;

    // We don't pre-fill with defaults anymore to keep them "hidden"
    // Only load if they actually exist in the config already
    if (user.name.isNotEmpty) notifier.updateUserName(user.name);
    if ((user.callSign ?? '').isNotEmpty) {
      notifier.updateUserCallSign(user.callSign!);
    }
    if ((user.pronouns ?? '').isNotEmpty) {
      notifier.updateUserPronouns(user.pronouns);
    }
    if ((user.notes ?? '').isNotEmpty) notifier.updateUserNotes(user.notes!);
    if (user.avatar != null) notifier.updateUserAvatar(user.avatar);

    final ident = updatedConfig.identity;
    // We don't pre-fill with defaults to keep them "hidden"
    if (ident.name != 'Ghost' && ident.name.isNotEmpty) {
      notifier.updateIdentName(ident.name);
    }
    if ((ident.creature ?? '').isNotEmpty &&
        ident.creature != 'Digital Ghost') {
      notifier.updateIdentCreature(ident.creature!);
    }
    if ((ident.vibe ?? '').isNotEmpty &&
        ident.vibe != 'Friendly, analytical, and economically accountable') {
      notifier.updateIdentVibe(ident.vibe!);
    }
    if ((ident.emoji ?? '').isNotEmpty && ident.emoji != '👻') {
      notifier.updateIdentEmoji(ident.emoji!);
    }
    if ((ident.notes ?? '').isNotEmpty) notifier.updateIdentNotes(ident.notes!);
    if (ident.avatar != null) notifier.updateIdentAvatar(ident.avatar);

    final ws = agent.workspace ?? '';
    notifier.updateWorkspace(ws);
    _workspaceCtrl.text = ws;

    // Sync other controllers
    final currentState = ref.read(setupWizardProvider);
    _userNameCtrl.text = currentState.userName;
    _userCallSignCtrl.text = currentState.userCallSign;
    _userNotesCtrl.text = currentState.userNotes;
    _userAvatarCtrl.text = currentState.userAvatar ?? '';

    _identNameCtrl.text = currentState.identName;
    _identCreatureCtrl.text = currentState.identCreature;
    _identVibeCtrl.text = currentState.identVibe;
    _identEmojiCtrl.text = currentState.identEmoji;
    _identNotesCtrl.text = currentState.identNotes;
    _identAvatarCtrl.text = currentState.identAvatar ?? '';

    // Set initial language
    if (mounted) {
      notifier.updateLanguage(context.locale.languageCode);
    }

    // Load existing API key if provider is set
    if (agent.provider != null) {
      notifier.updateProvider(agent.provider);
      // Fetch the actual key from the vault if it exists
      final key = await ref.read(configProvider.notifier).getKey(
        agent.provider == 'google' ? 'google_api_key' : '${agent.provider}_api_key',
      );
      if (key != null && key.isNotEmpty) {
        notifier.updateApiKey(key);
        // If we have a key, try to verify it to load models
        if (AppConstants.isLocalProvider(agent.provider!)) {
          await notifier.fetchLocalModels(agent.provider!);
        } else {
          await notifier.verifyKey();
        }
      }
    }
  }

  void _goNext() {
    final state = ref.read(setupWizardProvider);
    if (state.currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      ref.read(setupWizardProvider.notifier).setStep(state.currentStep + 1);
    }
  }

  void _goBack() {
    final state = ref.read(setupWizardProvider);
    if (state.currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      ref.read(setupWizardProvider.notifier).setStep(state.currentStep - 1);
    }
  }

  // ---- Next button enabled logic ----

  bool _canGoNext(SetupWizardState state) {
    switch (state.currentStep) {
      case 0:
        return true; // Language: always OK
      case 1:
        return true; // Setup Type: always OK (user picks card)
      case 2:
        return state.keyVerified && state.selectedModel != null;
      case 3:
      case 4:
      case 5:
        return true; // Workspace: optional
      default:
        return true;
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    // Watch locale to ensure rebuild of tabs and header on language change
    context.locale;
    final state = ref.watch(setupWizardProvider);

    // Sync API key controller if state changes from outside (e.g. provider detection)
    ref.listen(setupWizardProvider.select((s) => s.apiKey), (prev, next) {
      if (next != _apiKeyCtrl.text) {
        _apiKeyCtrl.text = next ?? '';
      }
    });

    // Sync PageController if state changes from within a step (e.g. Restore/Fresh selection)
    ref.listen(setupWizardProvider.select((s) => s.currentStep), (prev, next) {
      if (_pageController.hasClients &&
          _pageController.page?.round() != next) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(state),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const WizardStepLanguage(),
                const WizardStepRestore(),
                WizardStepProvider(state: state, apiKeyController: _apiKeyCtrl),
                WizardStepUser(
                  state: state,
                  nameController: _userNameCtrl,
                  callSignController: _userCallSignCtrl,
                  notesController: _userNotesCtrl,
                  avatarController: _userAvatarCtrl,
                  avatarNonce: _avatarNonces['user_avatar'] ?? 0,
                  onPickAvatar: () =>
                      _pickAvatar(_userAvatarCtrl, 'user_avatar'),
                ),
                WizardStepIdentity(
                  state: state,
                  nameController: _identNameCtrl,
                  creatureController: _identCreatureCtrl,
                  vibeController: _identVibeCtrl,
                  emojiController: _identEmojiCtrl,
                  notesController: _identNotesCtrl,
                  avatarController: _identAvatarCtrl,
                  avatarNonce: _avatarNonces['identity_avatar'] ?? 0,
                  onPickAvatar: () =>
                      _pickAvatar(_identAvatarCtrl, 'identity_avatar'),
                ),
                WizardStepWorkspace(
                  state: state,
                  workspaceController: _workspaceCtrl,
                ),
              ],
            ),
          ),
          _buildNavButtons(state),
        ],
      ),
    );
  }

  Widget _buildHeader(SetupWizardState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
      decoration: const BoxDecoration(color: AppColors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Image.asset(AppConstants.logoGhost, height: 60, width: 60),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppConstants.appName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: AppConstants.fontSizeDisplay,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'wizard.tagline'.tr(),
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: AppConstants.fontSizeCaption,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                'wizard.step_of'.tr(
                  namedArgs: {
                    'current': (state.currentStep + 1).toString(),
                    'total': _totalSteps.toString(),
                  },
                ),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: AppConstants.fontSizeLabelTiny,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'wizard.subtitle'.tr(),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: AppConstants.fontSizeSubhead,
            ),
          ),
          const SizedBox(height: 16),
          WizardStepIndicator(
            currentStep: state.currentStep,
            totalSteps: _totalSteps,
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons(SetupWizardState state) {
    final isLast = state.currentStep == _totalSteps - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: AppColors.surface,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (state.currentStep > 0)
            AppNavButton(
              onPressed: state.saving ? null : _goBack,
              label: 'wizard.back',
              icon: Icons.arrow_back,
            )
          else
            const SizedBox.shrink(),
          AppNavButton(
            onPressed: state.saving
                ? null
                : _canGoNext(state)
                ? (isLast ? _save : _goNext)
                : null,
            isPrimary: true,
            label: state.saving
                ? 'wizard.saving'
                : isLast
                ? 'wizard.save'
                : 'wizard.next',
            icon: state.saving
                ? null
                : (isLast ? Icons.check_circle : Icons.arrow_forward),
          ),
        ],
      ),
    );
  }

  // _label, _textField removed — use AppFormLabel / AppFormField.text() from app_styles.dart

  Future<void> _save() async {
    try {
      await ref.read(setupWizardProvider.notifier).save();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  Future<String?> _pickAvatar(
    TextEditingController controller,
    String uploadName,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final name = result.files.single.name;
        final wsUrl = await ref.read(gatewayUrlProvider.future);

        final wizardNotifier = ref.read(setupWizardProvider.notifier);
        final String? path = await ref
            .read(configProvider.notifier)
            .uploadAvatar(name, bytes, wsUrl);
        if (path != null) {
          controller.text = path;
          if (uploadName == 'user_avatar') {
            wizardNotifier.updateUserAvatar(path);
          } else {
            wizardNotifier.updateIdentAvatar(path);
          }
          setState(() {
            _avatarNonces[uploadName] = (_avatarNonces[uploadName] ?? 0) + 1;
          });
          return path;
        }
      }
    } catch (e) {
      AppSnackBar.showError(
        context,
        'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}),
      );
    }
    return null;
  }
}
