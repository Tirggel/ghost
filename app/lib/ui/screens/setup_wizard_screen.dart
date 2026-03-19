import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/setup_wizard_provider.dart';
import '../widgets/setup_wizard/wizard_step_language.dart';
import '../widgets/setup_wizard/wizard_step_provider.dart';
import '../widgets/setup_wizard/wizard_step_user.dart';
import '../widgets/setup_wizard/wizard_step_identity.dart';
import '../widgets/setup_wizard/wizard_step_workspace.dart';
import '../widgets/setup_wizard/wizard_step_telegram.dart';
import '../widgets/app_styles.dart';

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
  final _identEmojiCtrl = TextEditingController(text: '👻');
  final _identNotesCtrl = TextEditingController();
  final _identAvatarCtrl = TextEditingController();
  final _workspaceCtrl = TextEditingController();
  final _tgTokenCtrl = TextEditingController();

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
    _tgTokenCtrl.dispose();
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
    if ((user.callSign ?? '').isNotEmpty) notifier.updateUserCallSign(user.callSign!);
    if ((user.pronouns ?? '').isNotEmpty) notifier.updateUserPronouns(user.pronouns);
    if ((user.notes ?? '').isNotEmpty) notifier.updateUserNotes(user.notes!);
    if (user.avatar != null) notifier.updateUserAvatar(user.avatar);

    final ident = updatedConfig.identity;
    // We don't pre-fill with defaults to keep them "hidden"
    if (ident.name != 'Ghost' && ident.name.isNotEmpty) notifier.updateIdentName(ident.name);
    if ((ident.creature ?? '').isNotEmpty && ident.creature != 'Digital Ghost') {
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

    // Load Telegram config
    final channels = updatedConfig['channels'] as Map<String, dynamic>?;
    final tgConfig = channels?['telegram'] as Map<String, dynamic>?;
    if (tgConfig != null && tgConfig['enabled'] == true) {
      try {
        final client = ref.read(gatewayClientProvider);
        final res = await client.call('config.getTelegramToken');
        final token = res['token'] as String? ?? '';
        if (token.isNotEmpty) {
          notifier.updateTgToken(token);
          _tgTokenCtrl.text = token;
          await notifier.verifyTelegram();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Error restoring Telegram token: $e');
      }
    }

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
        return state.keyVerified && state.selectedModel != null;
      case 2:
      case 3:
      case 4:
        return true; // User / Identity / Workspace: optional
      case 5:
        return true; // Telegram: optional, Save always enabled
      default:
        return true;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.errorDark : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    // Watch locale to ensure rebuild of tabs and header on language change
    context.locale;
    final state = ref.watch(setupWizardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          _buildStepIndicator(state),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const WizardStepLanguage(),
                WizardStepProvider(
                  state: state,
                  apiKeyController: _apiKeyCtrl,
                ),
                WizardStepUser(
                  state: state,
                  nameController: _userNameCtrl,
                  callSignController: _userCallSignCtrl,
                  notesController: _userNotesCtrl,
                  avatarController: _userAvatarCtrl,
                  avatarNonce: _avatarNonces['user_avatar'] ?? 0,
                  onPickAvatar: () => _pickAvatar(_userAvatarCtrl, 'user_avatar'),
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
                  showSnackBar: _showSnackBar,
                ),
                WizardStepTelegram(
                  state: state,
                  tgTokenController: _tgTokenCtrl,
                ),
              ],
            ),
          ),
          _buildNavButtons(state),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
      decoration: const BoxDecoration(
        color: AppColors.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: AppConstants.fontSizeDisplay,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'wizard.subtitle'.tr(),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: AppConstants.fontSizeSubhead,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(SetupWizardState state) {
    final stepKeys = [
      'wizard.step_language',
      'wizard.step_provider',
      'wizard.step_user',
      'wizard.step_identity',
      'wizard.step_workspace',
      'wizard.step_telegram',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      child: AppDropdownField<int>(
        value: state.currentStep,
        items: List.generate(stepKeys.length, (index) => index),
        onChanged: (index) {
          if (index == null) return;
          final state = ref.read(setupWizardProvider);
          
          // Block navigation to "Your Profile" (index 2) and beyond if key not verified
          if (index >= 2 &&
              (!state.keyVerified || state.selectedModel == null)) {
            _showSnackBar(
              'wizard.errors.key_required_for_next'.tr(),
              isError: true,
            );
            return;
          }

          // Prevent jumping too far ahead (more than one step)
          if (index <= state.currentStep || index == state.currentStep + 1) {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
            ref.read(setupWizardProvider.notifier).setStep(index);
          } else {
            _showSnackBar('wizard.errors.step_by_step'.tr(), isError: true);
          }
        },
        displayValue: (index) => stepKeys[index].tr(),
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
        final String? path = await ref.read(configProvider.notifier).uploadAvatar(name, bytes, wsUrl);
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
      _showSnackBar(
        'file_picker.pick_error'.tr(namedArgs: {'error': e.toString()}),
        isError: true,
      );
    }
    return null;
  }
}
