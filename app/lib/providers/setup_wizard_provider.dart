import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_provider.dart';
import '../core/error_formatter.dart';

class SetupWizardState {
  final int currentStep;
  final String? selectedProvider;
  final String? apiKey;
  final bool verifyingKey;
  final bool keyVerified;
  final String? keyError;
  final List<String> models;
  final String? selectedModel;
  final bool loadingModels;
  final String userName;
  final String userCallSign;
  final String userPronouns;
  final String userNotes;
  final String? userAvatar;
  final String? baseUrl;
  final bool isLocalProvider;
  final bool serviceDetected;
  final String identName;
  final String identCreature;
  final String identVibe;
  final String identEmoji;
  final String identNotes;
  final String? identAvatar;
  final String workspace;
  final bool saving;
  final String language;

  SetupWizardState({
    this.currentStep = 0,
    this.selectedProvider,
    this.apiKey,
    this.verifyingKey = false,
    this.keyVerified = false,
    this.keyError,
    this.models = const [],
    this.selectedModel,
    this.loadingModels = false,
    this.userName = '',
    this.userCallSign = '',
    this.userPronouns = '',
    this.userNotes = '',
    this.userAvatar,
    this.baseUrl,
    this.isLocalProvider = false,
    this.serviceDetected = false,
    this.identName = '',
    this.identCreature = '',
    this.identVibe = '',
    this.identEmoji = '👻',
    this.identNotes = '',
    this.identAvatar,
    this.workspace = '',
    this.saving = false,
    this.language = 'en',
  });

  SetupWizardState copyWith({
    int? currentStep,
    Object? selectedProvider = _sentinel,
    Object? apiKey = _sentinel,
    bool? verifyingKey,
    bool? keyVerified,
    Object? keyError = _sentinel,
    List<String>? models,
    Object? selectedModel = _sentinel,
    bool? loadingModels,
    String? userName,
    String? userCallSign,
    String? userPronouns,
    String? userNotes,
    Object? userAvatar = _sentinel,
    Object? baseUrl = _sentinel,
    bool? isLocalProvider,
    bool? serviceDetected,
    String? identName,
    String? identCreature,
    String? identVibe,
    String? identEmoji,
    String? identNotes,
    Object? identAvatar = _sentinel,
    String? workspace,
    bool? saving,
    String? language,
  }) {
    return SetupWizardState(
      currentStep: currentStep ?? this.currentStep,
      selectedProvider: selectedProvider == _sentinel
          ? this.selectedProvider
          : (selectedProvider as String?),
      apiKey: apiKey == _sentinel ? this.apiKey : (apiKey as String?),
      verifyingKey: verifyingKey ?? this.verifyingKey,
      keyVerified: keyVerified ?? this.keyVerified,
      keyError: keyError == _sentinel ? this.keyError : (keyError as String?),
      models: models ?? this.models,
      selectedModel: selectedModel == _sentinel
          ? this.selectedModel
          : (selectedModel as String?),
      loadingModels: loadingModels ?? this.loadingModels,
      userName: userName ?? this.userName,
      userCallSign: userCallSign ?? this.userCallSign,
      userPronouns: userPronouns ?? this.userPronouns,
      userNotes: userNotes ?? this.userNotes,
      userAvatar:
          userAvatar == _sentinel ? this.userAvatar : (userAvatar as String?),
      baseUrl: baseUrl == _sentinel ? this.baseUrl : (baseUrl as String?),
      isLocalProvider: isLocalProvider ?? this.isLocalProvider,
      serviceDetected: serviceDetected ?? this.serviceDetected,
      identName: identName ?? this.identName,
      identCreature: identCreature ?? this.identCreature,
      identVibe: identVibe ?? this.identVibe,
      identEmoji: identEmoji ?? this.identEmoji,
      identNotes: identNotes ?? this.identNotes,
      identAvatar:
          identAvatar == _sentinel ? this.identAvatar : (identAvatar as String?),
      workspace: workspace ?? this.workspace,
      saving: saving ?? this.saving,
      language: language ?? this.language,
    );
  }
}

const _sentinel = Object();

final setupWizardProvider =
    NotifierProvider<SetupWizardNotifier, SetupWizardState>(() {
      return SetupWizardNotifier();
    });

class SetupWizardNotifier extends Notifier<SetupWizardState> {
  @override
  SetupWizardState build() {
    return SetupWizardState();
  }

  void setStep(int step) => state = state.copyWith(currentStep: step);

  void updateLanguage(String lang) {
    state = state.copyWith(language: lang);
  }

  static const localProviders = ['ollama', 'ipex-llm', 'vllm', 'litellm', 'lmstudio'];

  void updateProvider(String? provider) {
    final config = ref.read(configProvider);
    final isLocal = localProviders.contains(provider);
    
    String? detectedUrl;
    if (isLocal) {
      final detectedList = config.detectedLocalProviders;
      final detected = detectedList.firstWhere(
        (dp) => dp['id'] == provider,
        orElse: () => <String, String>{},
      );
      if (detected.containsKey('url')) {
        detectedUrl = detected['url'];
      } else {
        // Fallback to standard defaults if not detected
        if (provider == 'ollama') detectedUrl = 'http://localhost:11434';
        if (provider == 'lmstudio') detectedUrl = 'http://localhost:1234';
      }
    }

    state = state.copyWith(
      selectedProvider: provider,
      isLocalProvider: isLocal,
      serviceDetected: false, // Don't show detected card until verified
      baseUrl: detectedUrl,
      apiKey: detectedUrl, // Set apiKey even if null to trigger listener
      keyVerified: false, // Manual verification required
      keyError: null,
      models: [],
      selectedModel: null,
    );
    // Removed automatic fetchLocalModels(provider!);
  }

  Future<void> fetchLocalModels(String provider) async {
    state = state.copyWith(loadingModels: true, keyError: null);
    try {
      final models = await ref
          .read(configProvider.notifier)
          .listModels(provider, state.baseUrl);
      state = state.copyWith(
        loadingModels: false,
        keyVerified: models.isNotEmpty,
        serviceDetected: models.isNotEmpty, // Show success card now
        models: models,
        selectedModel: models.isNotEmpty ? models.first : null,
      );
    } catch (e) {
      state = state.copyWith(
        loadingModels: false,
        keyVerified: false,
        keyError: ErrorFormatter.format(e),
      );
    }
  }

  void updateApiKey(String key) {
    if (state.isLocalProvider) {
      state = state.copyWith(baseUrl: key, apiKey: key, keyVerified: false, keyError: null);
    } else {
      state = state.copyWith(apiKey: key, keyVerified: false, keyError: null);
    }
  }

  Future<void> verifyKey() async {
    if (state.selectedProvider == null || state.apiKey == null) return;
    state = state.copyWith(verifyingKey: true, keyError: null);
    try {
      final res = await ref
          .read(configProvider.notifier)
          .testKey(state.selectedProvider!, state.apiKey!);
      if (res['status'] == 'ok') {
        final models = await ref
            .read(configProvider.notifier)
            .listModels(state.selectedProvider!, state.apiKey!);
        state = state.copyWith(
          verifyingKey: false,
          keyVerified: true,
          models: models,
          selectedModel: models.isNotEmpty ? models.first : null,
        );
      } else {
        state = state.copyWith(
          verifyingKey: false,
          keyError: ErrorFormatter.format(res['message']),
        );
      }
    } catch (e) {
      state = state.copyWith(verifyingKey: false, keyError: ErrorFormatter.format(e));
    }
  }


  void updateSelectedModel(String? model) {
    state = state.copyWith(selectedModel: model);
  }

  void updateUserName(String val) {
    state = state.copyWith(userName: val);
  }
  void updateUserCallSign(String val) {
    state = state.copyWith(userCallSign: val);
  }
  void updateUserPronouns(String? val) {
    final clean = (val == null || val.isEmpty) ? 'Ask me' : val;
    state = state.copyWith(userPronouns: clean);
  }

  void updateUserNotes(String val) {
    state = state.copyWith(userNotes: val);
  }
  void updateUserAvatar(String? val) {
    state = state.copyWith(userAvatar: val);
  }

  void updateIdentName(String val) {
    state = state.copyWith(identName: val);
  }
  void updateIdentCreature(String val) {
    state = state.copyWith(identCreature: val);
  }
  void updateIdentVibe(String val) {
    state = state.copyWith(identVibe: val);
  }
  void updateIdentEmoji(String val) {
    state = state.copyWith(identEmoji: val);
  }
  void updateIdentNotes(String val) {
    state = state.copyWith(identNotes: val);
  }
  void updateIdentAvatar(String? val) {
    state = state.copyWith(identAvatar: val);
  }


  void updateWorkspace(String val) {
    state = state.copyWith(workspace: val);
  }

  Future<void> save() async {
    state = state.copyWith(saving: true);
    final config = ref.read(configProvider.notifier);
    try {
      if (state.selectedProvider != null && state.apiKey != null) {
        // If local provider, apiKey holds the baseUrl
        await config.setKey(state.selectedProvider!, state.apiKey!);
      }
      if (state.selectedModel != null) {
        await config.setModel(
          state.selectedModel!,
          provider: state.selectedProvider,
        );
      }
      await config.updateUser({
        'name': state.userName.isEmpty ? 'wizard.defaults.user_name'.tr() : state.userName,
        'callSign': state.userCallSign.isEmpty ? 'wizard.defaults.user_call_sign'.tr() : state.userCallSign,
        'pronouns': state.userPronouns.isEmpty ? 'wizard.defaults.user_pronouns'.tr() : state.userPronouns,
        'notes': state.userNotes.isEmpty ? 'wizard.defaults.user_notes'.tr() : state.userNotes,
        'avatar': state.userAvatar,
        'language': state.language,
      });
      await config.updateIdentity({
        'name': state.identName.isEmpty ? 'wizard.defaults.ident_name'.tr() : state.identName,
        'creature': state.identCreature.isEmpty ? 'wizard.defaults.ident_creature'.tr() : state.identCreature,
        'vibe': state.identVibe.isEmpty ? 'wizard.defaults.ident_vibe'.tr() : state.identVibe,
        'emoji': state.identEmoji.isEmpty ? 'wizard.defaults.ident_emoji'.tr() : state.identEmoji,
        'notes': state.identNotes.isEmpty 
          ? 'wizard.defaults.ident_notes'.tr(namedArgs: {'lang': state.language == 'de' ? 'Deutsch' : 'English'}) 
          : state.identNotes,
        'avatar': state.identAvatar,
      });
      if (state.workspace.isNotEmpty) {
        await config.updateAgentWorkspace(state.workspace);
      }
      state = state.copyWith(saving: false);
    } catch (_) {
      state = state.copyWith(saving: false);
      rethrow;
    }
  }
}
