class UserConfig {
  final String name;
  final String? callSign;
  final String? pronouns;
  final String? notes;
  final String? avatar;
  final String? language;
  final String? timezone;

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
  final String name;
  final String? creature;
  final String? vibe;
  final String? emoji;
  final String? notes;
  final String? avatar;

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
  final String? provider;
  final String? model;
  final String? workspace;
  final List<String> skills;

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

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'model': model,
      'workspace': workspace,
      'skills': skills,
    };
  }
}

class ModelCapabilities {
  final bool supportsText;
  final bool supportsImage;
  final bool supportsVideo;
  final bool supportsAudio;
  final bool supportsPdf;

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

  Map<String, dynamic> toJson() => {
        'text': supportsText,
        'image': supportsImage,
        'video': supportsVideo,
        'audio': supportsAudio,
        'pdf': supportsPdf,
      };
}

class MemoryConfig {
  final bool enabled;
  final bool ragEnabled;
  final String backend;
  final String embeddingProvider;
  final String embeddingModel;
  final int chunkSize;
  final int chunkOverlap;
  final double vectorWeight;
  final double bm25Weight;

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
  final String profile;
  final List<String> allow;
  final List<String> deny;
  final bool browserHeadless;

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

  Map<String, dynamic> toJson() {
    return {
      'profile': profile,
      'allow': allow,
      'deny': deny,
      'browserHeadless': browserHeadless,
    };
  }
}

class AppConfig {
  final UserConfig user;
  final IdentityConfig identity;
  final AgentConfig agent;
  final MemoryConfig memory;
  final ToolsConfig tools;
  final Map<String, dynamic> vault;
  final Map<String, dynamic> channels;
  final Map<String, dynamic> integrations;
  final List<dynamic> customAgents;
  final List<dynamic> history;
  final List<Map<String, String>> detectedLocalProviders;

  AppConfig({
    required this.user,
    required this.identity,
    required this.agent,
    required this.memory,
    required this.tools,
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
      vault: json['vault'] as Map<String, dynamic>? ?? {},
      channels: json['channels'] as Map<String, dynamic>? ?? {},
      integrations: json['integrations'] as Map<String, dynamic>? ?? {},
      customAgents: json['customAgents'] as List<dynamic>? ?? [],
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
    );
  }

  bool get isEmpty => user.name.isEmpty && agent.provider == null;
  bool get isNotEmpty => !isEmpty;

  List<String> get vaultKeys =>
      (vault['keys'] as List<dynamic>?)?.cast<String>() ?? [];

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
