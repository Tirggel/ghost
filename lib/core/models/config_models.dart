import '../constants.dart';

class UserConfig {

  UserConfig({
    required this.name,
    this.callSign,
    this.pronouns,
    this.notes,
    this.avatar,
    this.language,
    this.timezone,
  });

  factory UserConfig.fromJson(Map<String, dynamic> json) {
    return UserConfig(
      name: json['name'] as String? ?? '',
      callSign: json['callSign'] as String?,
      pronouns: json['pronouns'] as String?,
      notes: json['notes'] as String?,
      avatar: json['avatar'] as String?,
      language: json['language'] as String?,
      timezone: json['timezone'] as String?,
    );
  }
  final String name;
  final String? callSign;
  final String? pronouns;
  final String? notes;
  final String? avatar;
  final String? language;
  final String? timezone;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'callSign': callSign,
      'pronouns': pronouns,
      'notes': notes,
      'avatar': avatar,
      'language': language,
      'timezone': timezone,
    };
  }

  dynamic operator [](String key) {
    switch (key) {
      case 'name': return name;
      case 'callSign': return callSign;
      case 'pronouns': return pronouns;
      case 'notes': return notes;
      case 'avatar': return avatar;
      case 'language': return language;
      case 'timezone': return timezone;
      default: return null;
    }
  }
}

class IdentityConfig {

  IdentityConfig({
    required this.name,
    this.creature,
    this.vibe,
    this.emoji,
    this.notes,
    this.avatar,
  });

  factory IdentityConfig.fromJson(Map<String, dynamic> json) {
    return IdentityConfig(
      name: json['name'] as String? ?? 'Ghost',
      creature: json['creature'] as String?,
      vibe: json['vibe'] as String?,
      emoji: json['emoji'] as String?,
      notes: json['notes'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
  final String name;
  final String? creature;
  final String? vibe;
  final String? emoji;
  final String? notes;
  final String? avatar;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'creature': creature,
      'vibe': vibe,
      'emoji': emoji,
      'notes': notes,
      'avatar': avatar,
    };
  }

  dynamic operator [](String key) {
    switch (key) {
      case 'name': return name;
      case 'creature': return creature;
      case 'vibe': return vibe;
      case 'emoji': return emoji;
      case 'notes': return notes;
      case 'avatar': return avatar;
      default: return null;
    }
  }
}

class AgentConfig {

  AgentConfig({
    this.provider,
    this.model,
    this.workspace,
    this.skills = const [],
  });

  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    return AgentConfig(
      provider: json['provider'] as String?,
      model: json['model'] as String?,
      workspace: json['workspace'] as String?,
      skills: (json['skills'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
  final String? provider;
  final String? model;
  final String? workspace;
  final List<String> skills;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'model': model,
      'workspace': workspace,
      'skills': skills,
    };
  }
}

class CustomAgentConfig {
  const CustomAgentConfig({
    required this.id,
    required this.name,
    this.systemPrompt = '',
    this.cronSchedule,
    this.cronMessage = 'Run your scheduled task.',
    this.model,
    this.provider,
    this.skills = const [],
    this.enabled = true,
    this.avatar,
    this.shouldSendChatHistory = true,
  });

  factory CustomAgentConfig.fromJson(Map<String, dynamic> json) {
    return CustomAgentConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      systemPrompt: json['systemPrompt'] as String? ?? '',
      cronSchedule: json['cronSchedule'] as String?,
      cronMessage: json['cronMessage'] as String? ?? 'Run your scheduled task.',
      model: json['model'] as String?,
      provider: json['provider'] as String?,
      skills: (json['skills'] as List<dynamic>?)?.cast<String>() ?? [],
      enabled: json['enabled'] as bool? ?? true,
      avatar: json['avatar'] as String?,
      shouldSendChatHistory: json['shouldSendChatHistory'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String systemPrompt;
  final String? cronSchedule;
  final String cronMessage;
  final String? model;
  final String? provider;
  final List<String> skills;
  final bool enabled;
  final String? avatar;
  final bool shouldSendChatHistory;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'systemPrompt': systemPrompt,
        if (cronSchedule != null) 'cronSchedule': cronSchedule,
        'cronMessage': cronMessage,
        if (model != null) 'model': model,
        if (provider != null) 'provider': provider,
        'skills': skills,
        'enabled': enabled,
        if (avatar != null) 'avatar': avatar,
        'shouldSendChatHistory': shouldSendChatHistory,
      };

  CustomAgentConfig copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    String? cronSchedule,
    String? cronMessage,
    String? model,
    String? provider,
    List<String>? skills,
    bool? enabled,
    String? avatar,
    bool? shouldSendChatHistory,
  }) {
    return CustomAgentConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      cronSchedule: cronSchedule ?? this.cronSchedule,
      cronMessage: cronMessage ?? this.cronMessage,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      skills: skills ?? this.skills,
      enabled: enabled ?? this.enabled,
      avatar: avatar ?? this.avatar,
      shouldSendChatHistory:
          shouldSendChatHistory ?? this.shouldSendChatHistory,
    );
  }
}

class ModelCapabilities {

  const ModelCapabilities({
    this.supportsText = true,
    this.supportsImage = false,
    this.supportsVideo = false,
    this.supportsAudio = false,
    this.supportsPdf = false,
  });

  factory ModelCapabilities.textOnly() => const ModelCapabilities();

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) {
    return ModelCapabilities(
      supportsText: json['text'] as bool? ?? true,
      supportsImage: json['image'] as bool? ?? false,
      supportsVideo: json['video'] as bool? ?? false,
      supportsAudio: json['audio'] as bool? ?? false,
      supportsPdf: json['pdf'] as bool? ?? false,
    );
  }
  final bool supportsText;
  final bool supportsImage;
  final bool supportsVideo;
  final bool supportsAudio;
  final bool supportsPdf;

  Map<String, dynamic> toJson() => {
        'text': supportsText,
        'image': supportsImage,
        'video': supportsVideo,
        'audio': supportsAudio,
        'pdf': supportsPdf,
      };
}

class MemoryConfig {

  MemoryConfig({
    this.enabled = true,
    this.ragEnabled = false,
    this.backend = 'hive',
    this.embeddingProvider = '',
    this.embeddingModel = '',
    this.chunkSize = 400,
    this.chunkOverlap = 80,
    this.vectorWeight = 0.7,
    this.bm25Weight = 0.3,
  });

  factory MemoryConfig.fromJson(Map<String, dynamic> json) {
    return MemoryConfig(
      enabled: json['enabled'] as bool? ?? true,
      ragEnabled: json['ragEnabled'] as bool? ?? false,
      backend: json['backend'] as String? ?? 'hive',
      embeddingProvider: json['embeddingProvider'] as String? ?? '',
      embeddingModel: json['embeddingModel'] as String? ?? '',
      chunkSize: (json['chunkSize'] as num?)?.toInt() ?? 400,
      chunkOverlap: (json['chunkOverlap'] as num?)?.toInt() ?? 80,
      vectorWeight: (json['vectorWeight'] as num?)?.toDouble() ?? 0.7,
      bm25Weight: (json['bm25Weight'] as num?)?.toDouble() ?? 0.3,
    );
  }
  final bool enabled;
  final bool ragEnabled;
  final String backend;
  final String embeddingProvider;
  final String embeddingModel;
  final int chunkSize;
  final int chunkOverlap;
  final double vectorWeight;
  final double bm25Weight;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'ragEnabled': ragEnabled,
      'backend': backend,
      'embeddingProvider': embeddingProvider,
      'embeddingModel': embeddingModel,
      'chunkSize': chunkSize,
      'chunkOverlap': chunkOverlap,
      'vectorWeight': vectorWeight,
      'bm25Weight': bm25Weight,
    };
  }
}

class ToolsConfig {

  ToolsConfig({
    this.profile = 'full',
    this.allow = const [],
    this.deny = const [],
    this.browserHeadless = true,
  });

  factory ToolsConfig.fromJson(Map<String, dynamic> json) {
    return ToolsConfig(
      profile: json['profile'] as String? ?? 'full',
      allow: (json['allow'] as List<dynamic>?)?.cast<String>() ?? [],
      deny: (json['deny'] as List<dynamic>?)?.cast<String>() ?? [],
      browserHeadless: json['browserHeadless'] as bool? ?? true,
    );
  }
  final String profile;
  final List<String> allow;
  final List<String> deny;
  final bool browserHeadless;

  Map<String, dynamic> toJson() {
    return {
      'profile': profile,
      'allow': allow,
      'deny': deny,
      'browserHeadless': browserHeadless,
    };
  }
}

enum SecurityLevel { none, low, medium, high }

class SecurityConfig {

  SecurityConfig({
    this.level = SecurityLevel.none,
    this.humanInTheLoop = false,
    this.promptHardening = false,
    this.restrictNetwork = false,
    this.promptAnalyzers = false,
  });

  factory SecurityConfig.fromJson(Map<String, dynamic> json) {
    return SecurityConfig(
      level: SecurityLevel.values.firstWhere(
        (lvl) => lvl.name == (json['level'] as String?),
        orElse: () => SecurityLevel.none,
      ),
      humanInTheLoop: json['humanInTheLoop'] as bool? ?? false,
      promptHardening: json['promptHardening'] as bool? ?? false,
      restrictNetwork: json['restrictNetwork'] as bool? ?? false,
      promptAnalyzers: json['promptAnalyzers'] as bool? ?? false,
    );
  }
  final SecurityLevel level;
  final bool humanInTheLoop;
  final bool promptHardening;
  final bool restrictNetwork;
  final bool promptAnalyzers;

  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'humanInTheLoop': humanInTheLoop,
      'promptHardening': promptHardening,
      'restrictNetwork': restrictNetwork,
      'promptAnalyzers': promptAnalyzers,
    };
  }

  SecurityConfig copyWith({
    SecurityLevel? level,
    bool? humanInTheLoop,
    bool? promptHardening,
    bool? restrictNetwork,
    bool? promptAnalyzers,
  }) {
    return SecurityConfig(
      level: level ?? this.level,
      humanInTheLoop: humanInTheLoop ?? this.humanInTheLoop,
      promptHardening: promptHardening ?? this.promptHardening,
      restrictNetwork: restrictNetwork ?? this.restrictNetwork,
      promptAnalyzers: promptAnalyzers ?? this.promptAnalyzers,
    );
  }
}

class AppConfig {

  AppConfig({
    required this.user,
    required this.identity,
    required this.agent,
    required this.memory,
    required this.tools,
    required this.security,
    this.vault = const {},
    this.channels = const {},
    this.integrations = const {},
    this.customAgents = const [],
    this.history = const [],
    this.detectedLocalProviders = const [],
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      user: UserConfig.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      identity: IdentityConfig.fromJson(
        json['identity'] as Map<String, dynamic>? ?? {},
      ),
      agent: AgentConfig.fromJson(json['agent'] as Map<String, dynamic>? ?? {}),
      memory: MemoryConfig.fromJson(json['memory'] as Map<String, dynamic>? ?? {}),
      tools: ToolsConfig.fromJson(json['tools'] as Map<String, dynamic>? ?? {}),
      security: SecurityConfig.fromJson(json['security'] as Map<String, dynamic>? ?? {}),
      vault: json['vault'] as Map<String, dynamic>? ?? {},
      channels: json['channels'] as Map<String, dynamic>? ?? {},
      integrations: json['integrations'] as Map<String, dynamic>? ?? {},
      customAgents: (json['customAgents'] as List<dynamic>? ?? [])
          .map((e) => CustomAgentConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      history: json['history'] as List<dynamic>? ?? [],
      detectedLocalProviders: (json['detectedLocalProviders'] as List<dynamic>? ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
    );
  }

  factory AppConfig.empty() {
    return AppConfig(
      user: UserConfig(name: ''),
      identity: IdentityConfig(name: 'Ghost'),
      agent: AgentConfig(),
      memory: MemoryConfig(),
      tools: ToolsConfig(),
      security: SecurityConfig(),
    );
  }
  final UserConfig user;
  final IdentityConfig identity;
  final AgentConfig agent;
  final MemoryConfig memory;
  final ToolsConfig tools;
  final SecurityConfig security;
  final Map<String, dynamic> vault;
  final Map<String, dynamic> channels;
  final Map<String, dynamic> integrations;
  final List<CustomAgentConfig> customAgents;
  final List<dynamic> history;
  final List<Map<String, String>> detectedLocalProviders;

  bool get isEmpty => user.name.isEmpty && agent.provider == null;
  bool get isNotEmpty => !isEmpty;

  List<String> get vaultKeys =>
      (vault['keys'] as List<dynamic>?)?.cast<String>() ?? [];

  bool isProviderConfigured(String provider) {
    if (AppConstants.isLocalProvider(provider)) {
      final isAlreadySet = vaultKeys.contains('${provider}_base_url');
      final isDetected =
          detectedLocalProviders.any((dp) => dp['id'] == provider);
      return isAlreadySet || isDetected;
    }
    final keyName = provider == 'google' ? 'google_api_key' : '${provider}_api_key';
    return vaultKeys.contains(keyName);
  }

  List<Map<String, String>> getAvailableProviders(
    List<Map<String, String>> allProviders,
  ) {
    return allProviders.where((p) => isProviderConfigured(p['id']!)).toList();
  }

  dynamic operator [](String key) {
    switch (key) {
      case 'user': return user;
      case 'identity': return identity;
      case 'agent': return agent;
      case 'vault': return vault;
      case 'channels': return channels;
      case 'integrations': return integrations;
      case 'customAgents': return customAgents;
      case 'history': return history;
      default: return null;
    }
  }
}
