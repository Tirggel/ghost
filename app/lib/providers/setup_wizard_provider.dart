import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_provider.dart';

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
    String? selectedProvider,
    String? apiKey,
    bool? verifyingKey,
    bool? keyVerified,
    String? keyError,
    List<String>? models,
    String? selectedModel,
    bool? loadingModels,
    String? userName,
    String? userCallSign,
    String? userPronouns,
    String? userNotes,
    String? userAvatar,
    String? identName,
    String? identCreature,
    String? identVibe,
    String? identEmoji,
    String? identNotes,
    String? identAvatar,
    String? workspace,
    bool? saving,
    String? language,
  }) {
    return SetupWizardState(
      currentStep: currentStep ?? this.currentStep,
      selectedProvider: selectedProvider ?? this.selectedProvider,
      apiKey: apiKey ?? this.apiKey,
      verifyingKey: verifyingKey ?? this.verifyingKey,
      keyVerified: keyVerified ?? this.keyVerified,
      keyError: keyError ?? this.keyError,
      models: models ?? this.models,
      selectedModel: selectedModel ?? this.selectedModel,
      loadingModels: loadingModels ?? this.loadingModels,
      userName: userName ?? this.userName,
      userCallSign: userCallSign ?? this.userCallSign,
      userPronouns: userPronouns ?? this.userPronouns,
      userNotes: userNotes ?? this.userNotes,
      userAvatar: userAvatar ?? this.userAvatar,
      identName: identName ?? this.identName,
      identCreature: identCreature ?? this.identCreature,
      identVibe: identVibe ?? this.identVibe,
      identEmoji: identEmoji ?? this.identEmoji,
      identNotes: identNotes ?? this.identNotes,
      identAvatar: identAvatar ?? this.identAvatar,
      workspace: workspace ?? this.workspace,
      saving: saving ?? this.saving,
      language: language ?? this.language,
    );
  }
}

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

  void updateProvider(String? provider) {
    state = state.copyWith(
      selectedProvider: provider,
      keyVerified: provider == 'ollama',
      keyError: null,
      models: [],
      selectedModel: null,
    );
    if (provider == 'ollama') {
      fetchOllamaModels();
    }
  }

  void updateApiKey(String key) {
    state = state.copyWith(apiKey: key, keyVerified: false);
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
          keyError: res['message'] ?? 'Unknown error',
        );
      }
    } catch (e) {
      state = state.copyWith(verifyingKey: false, keyError: e.toString());
    }
  }

  Future<void> fetchOllamaModels() async {
    state = state.copyWith(loadingModels: true);
    try {
      final models = await ref
          .read(configProvider.notifier)
          .listModels('ollama', null);
      state = state.copyWith(
        loadingModels: false,
        keyVerified: true,
        models: models,
        selectedModel: models.isNotEmpty ? models.first : null,
      );
    } catch (_) {
      state = state.copyWith(loadingModels: false);
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
