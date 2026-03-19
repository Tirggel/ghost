// Ghost — Configuration schema validation.

import '../infra/errors.dart';
import 'config.dart';

/// Validates a [GhostConfig] and returns a list of validation errors.
/// Returns an empty list if the config is valid.
List<String> validateConfig(GhostConfig config) {
  final errors = <String>[];

  // Gateway validation
  _validateGateway(config.gateway, errors);

  // Agent validation
  _validateAgent(config.agent, errors);

  // Memory validation
  _validateMemory(config.memory, errors);

  // Session validation
  _validateSession(config.session, errors);

  // Tools validation
  _validateTools(config.tools, errors);

  // User validation
  _validateUser(config.user, errors);

  // Identity validation
  _validateIdentity(config.identity, errors);

  // Integrations validation
  _validateIntegrations(config.integrations, errors);

  // Custom Agents validation
  _validateCustomAgents(config.customAgents, errors);

  return errors;
}

/// Validates a config and throws [ConfigError] if invalid.
void assertConfigValid(GhostConfig config) {
  final errors = validateConfig(config);
  if (errors.isNotEmpty) {
    throw ConfigError(
      'Invalid configuration:\n  - ${errors.join('\n  - ')}',
      code: 'INVALID_CONFIG',
    );
  }
}

/// Validates raw JSON before parsing, returns errors found.
List<String> validateConfigJson(Map<String, dynamic> json) {
  final errors = <String>[];

  // Check top-level keys
  final validTopLevel = {
    'gateway',
    'agent',
    'channels',
    'tools',
    'memory',
    'session',
    'user',
    'identity',
    'integrations',
    'customAgents',
  };
  for (final key in json.keys) {
    if (!validTopLevel.contains(key)) {
      errors.add('Unknown top-level config key: "$key"');
    }
  }

  // Try to parse and validate
  try {
    final config = GhostConfig.fromJson(json);
    errors.addAll(validateConfig(config));
  } on TypeError catch (e) {
    errors.add('Type error in config: $e');
  } on FormatException catch (e) {
    errors.add('Format error in config: $e');
  }

  return errors;
}

void _validateGateway(GatewayConfig gateway, List<String> errors) {
  if (gateway.port < 1 || gateway.port > 65535) {
    errors.add(
      'gateway.port must be between 1 and 65535 (got ${gateway.port})',
    );
  }

  if (gateway.auth.mode == AuthMode.token && gateway.auth.tokenHash == null) {
    // Token mode without a hash is valid — means generate on first run
  }

  if (gateway.auth.mode == AuthMode.password &&
      gateway.auth.passwordHash == null) {
    errors.add(
      'gateway.auth.passwordHash is required when auth mode is "password"',
    );
  }

  // Warn: binding to all interfaces without auth
  if (gateway.bind == BindMode.all && gateway.auth.mode == AuthMode.none) {
    errors.add(
      'SECURITY: gateway.bind is "all" but auth mode is "none" — '
      'this exposes the gateway without authentication!',
    );
  }
}

void _validateAgent(AgentConfig agent, List<String> errors) {
  if (agent.maxTokens < 1) {
    errors.add('agent.maxTokens must be >= 1 (got ${agent.maxTokens})');
  }

  if (agent.maxTokens > 200000) {
    errors.add('agent.maxTokens exceeds 200000 (got ${agent.maxTokens})');
  }

  final validThinking = {'auto', 'off', 'low', 'high'};
  if (!validThinking.contains(agent.thinkingMode)) {
    errors.add(
      'agent.thinkingMode must be one of $validThinking '
      '(got "${agent.thinkingMode}")',
    );
  }
}

void _validateMemory(MemoryConfig memory, List<String> errors) {
  final validBackends = {'sqlite', 'hive', 'qmd'};
  if (!validBackends.contains(memory.backend)) {
    errors.add(
      'memory.backend must be one of $validBackends '
      '(got "${memory.backend}")',
    );
  }

  if (memory.chunkSize < 50) {
    errors.add('memory.chunkSize must be >= 50 (got ${memory.chunkSize})');
  }

  if (memory.chunkOverlap < 0) {
    errors.add('memory.chunkOverlap must be >= 0 (got ${memory.chunkOverlap})');
  }

  if (memory.chunkOverlap >= memory.chunkSize) {
    errors.add(
      'memory.chunkOverlap (${memory.chunkOverlap}) must be less than '
      'chunkSize (${memory.chunkSize})',
    );
  }

  final totalWeight = memory.vectorWeight + memory.bm25Weight;
  if ((totalWeight - 1.0).abs() > 0.01) {
    errors.add(
      'memory.vectorWeight + bm25Weight must equal 1.0 (got $totalWeight)',
    );
  }
}

void _validateSession(SessionConfig session, List<String> errors) {
  if (session.maxHistory < 1) {
    errors.add('session.maxHistory must be >= 1 (got ${session.maxHistory})');
  }

  if (session.pruneAfterDays < 0) {
    errors.add(
      'session.pruneAfterDays must be >= 0 (got ${session.pruneAfterDays})',
    );
  }

  final validFormats = {'jsonl', 'json'};
  if (!validFormats.contains(session.transcriptFormat)) {
    errors.add(
      'session.transcriptFormat must be one of $validFormats '
      '(got "${session.transcriptFormat}")',
    );
  }
}

void _validateTools(ToolsConfig tools, List<String> errors) {
  final validProfiles = {'minimal', 'coding', 'messaging', 'full'};
  if (!validProfiles.contains(tools.profile)) {
    errors.add(
      'tools.profile must be one of $validProfiles '
      '(got "${tools.profile}")',
    );
  }

  // Check for conflicts: same tool in allow and deny
  final conflicts = tools.allow.toSet().intersection(tools.deny.toSet());
  if (conflicts.isNotEmpty) {
    errors.add(
      'tools.allow and tools.deny have conflicting entries: $conflicts '
      '(deny always wins)',
    );
  }
}

void _validateUser(UserConfig user, List<String> errors) {
  // Mostly optional, but could validate timezone if needed
}

void _validateIdentity(IdentityConfig identity, List<String> errors) {
  if (identity.name.trim().isEmpty) {
    errors.add('identity.name must not be empty or whitespace');
  }
}

void _validateIntegrations(
    IntegrationsConfig integrations, List<String> errors) {
  // Validate integration specific fields if necessary
}

void _validateCustomAgents(
    List<CustomAgentConfig> agents, List<String> errors) {
  final ids = <String>{};
  for (final agent in agents) {
    if (agent.id.isEmpty) {
      errors.add('customAgents contains an agent with an empty id');
    } else if (ids.contains(agent.id)) {
      errors.add('Duplicate custom agent id: ${agent.id}');
    }
    ids.add(agent.id);

    if (agent.name.isEmpty) {
      errors.add('customAgent ${agent.id} must have a name');
    }
  }
}
