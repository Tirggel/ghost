// Ghost — Configuration RPC Router.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:hive_ce/hive.dart';
import 'dart:typed_data';
import '../config/io.dart';
import '../config/secure_storage.dart';
import '../gateway/server.dart';
import '../infra/errors.dart';
import '../agent/manager.dart';
import '../agent/providers/factory.dart';
import '../config/config.dart';
import '../channels/manager.dart';
import '../channels/telegram.dart';
import '../tools/google_workspace.dart';

final _log = Logger('Ghost.ConfigRouter');

/// Routes configuration requests from the Gateway.
class ConfigRouter {
  ConfigRouter({
    required this.gateway,
    required this.storage,
    required this.configPath,
    required this.agentManager,
    required this.channelManager,
  });

  final GatewayServer gateway;
  final SecureStorage storage;
  final String configPath;
  final AgentManager agentManager;
  final ChannelManager channelManager;

  /// Register config-related RPC methods.
  void register() {
    // 1. Get current config info
    gateway.rpcRegistry.register('config.get', (params, context) async {
      // Migrate any existing plaintext user/identity/agent from JSON to vault
      await _migrateUserIdentityToVault();
      await _migrateAgentToVault();
      await _migrateMemoryToVault();
      await _migrateCustomAgentsToVault();
      await _migrateAdditionalConfigsToVault();

      // We'll read the latest from disk to be sure
      final config = await loadConfig(configPath);

      // Load from vault (overrides any JSON values)
      final user = await _loadUserFromVault() ?? config.user;
      final identity = await _loadIdentityFromVault() ?? config.identity;
      final agent = await _loadAgentFromVault() ?? config.agent;
      final memory = await _loadMemoryFromVault() ?? config.memory;
      final customAgents =
          await _loadCustomAgentsFromVault() ?? config.customAgents;

      await _loadSessionFromVault() ?? config.session;
      final channels = await _loadChannelsFromVault() ?? config.channels;
      final tools = await _loadToolsFromVault() ?? config.tools;
      final integrations =
          await _loadIntegrationsFromVault() ?? config.integrations;

      return {
        'agent': agent.toJson(),
        'memory': memory.toJson(),
        'customAgents':
            customAgents.map((CustomAgentConfig a) => a.toJson()).toList(),
        'gateway': {
          'port': config.gateway.port,
          'verbose': config.gateway.verbose,
        },
        'user': user.toJson(),
        'identity': identity.toJson(),
        'integrations': integrations.toJson(),
        'channels': channels.toJson(),
        'tools': tools.toJson(),
        'vault': {
          'keys': await storage.listKeys(),
        },
        'detectedLocalProviders': await _detectLocalProviders(),
      };
    });

    // 1b. Get Telegram token from vault
    gateway.rpcRegistry.register('config.getTelegramToken',
        (params, context) async {
      final token = await storage.get('telegram_bot_token') ?? '';
      return {'token': token};
    });

    // 2. Set API Key
    gateway.rpcRegistry.register('config.setKey', (params, context) async {
      final service = params?['service'] as String?;
      final key = params?['key'] as String?;

      if (service == null || key == null) {
        throw ProtocolError('Missing required parameters: service, key');
      }

      final storageKey = _getStorageKey(service);
      if (key.isEmpty) {
        // Deletion attempt - check constraints
        final keys = await storage.listKeys();
        final providerKeys = keys
            .where((k) =>
                k.endsWith('_api_key') ||
                k == 'ollama_base_url' ||
                k == 'vllm_base_url' ||
                k == 'litellm_base_url')
            .toList();

        // 1. Ensure at least one provider remains
        if (providerKeys.length <= 1 && providerKeys.contains(storageKey)) {
          throw ProtocolError(
              'Löschen fehlgeschlagen: Es muss mindestens ein API-Key im System vorhanden sein.');
        }

        // 2. Ensure provider is not in use by Identity (Main Agent)
        final config = await loadConfig(configPath);
        final currentAgent = await _loadAgentFromVault() ?? config.agent;
        if (currentAgent.provider == service) {
          throw ProtocolError(
              'Löschen fehlgeschlagen: Der Provider "$service" wird aktuell von der Identität benutzt. '
              'Bitte wechsele zuerst bei der Identität den Provider und das Modell.');
        }

        // 3. Ensure provider is not in use by any Custom Agent
        final customAgents =
            await _loadCustomAgentsFromVault() ?? config.customAgents;
        for (final ca in customAgents) {
          if (ca.provider == service) {
            throw ProtocolError(
                'Löschen fehlgeschlagen: Der Provider "$service" wird aktuell vom Custom Agent "${ca.name}" benutzt. '
                'Bitte wechsele zuerst bei diesem Agent den Provider und das Modell.');
          }
        }

        await storage.remove(storageKey);
        _log.info('Securely removed $service key via RPC');
      } else {
        await storage.set(storageKey, key);
        _log.info('Securely updated $service key via RPC');
      }
      return {'status': 'ok'};
    });

    // 2b. Test an API key
    gateway.rpcRegistry.register('config.testKey', (params, context) async {
      final service = params?['service'] as String?;
      final key = params?['key'] as String?;

      if (service == null || key == null) {
        throw ProtocolError('Missing required parameters: service, key');
      }

      if (service == 'google_workspace') {
        final isValid = await GoogleWorkspaceClient.testConnection(storage);
        if (isValid) {
          return {'status': 'ok', 'message': 'Connection successful'};
        } else {
          return {
            'status': 'error',
            'message': 'Google Workspace token expired or invalid'
          };
        }
      }

      if (service == 'telegram') {
        final isValid = await TelegramChannel.testToken(key);
        if (isValid) {
          return {'status': 'ok', 'message': 'Connection successful'};
        } else {
          return {'status': 'error', 'message': 'Telegram token is invalid'};
        }
      }

      if (service == 'google_client_id_web' ||
          service == 'google_client_id_desktop' ||
          service == 'google_client_secret') {
        return {'status': 'ok', 'message': 'Skipped connection test'};
      }

      try {
        final isLocal =
            service == 'ollama' || service == 'vllm' || service == 'litellm';
        final apiKeyToTest = isLocal ? service : key;
        final baseUrlToTest = isLocal ? key : null;

        await ProviderFactory.testKey(
          provider: service,
          apiKey: apiKeyToTest,
          baseUrl: baseUrlToTest,
        );
        return {'status': 'ok', 'message': 'Connection successful'};
      } catch (e) {
        return {'status': 'error', 'message': e.toString()};
      }
    });

    // 2c. Test if a model supports embeddings
    gateway.rpcRegistry.register('config.testEmbedding',
        (params, context) async {
      final provider = params?['provider'] as String?;
      final model = params?['model'] as String?;
      if (provider == null || model == null) {
        throw ProtocolError('Missing required parameters: provider, model');
      }

      try {
        final embeddingProvider = await ProviderFactory.create(
          model: model,
          provider: provider,
          storage: storage,
        );
        // Try a real embedding call with a short test string
        final result = await embeddingProvider.embed('test', model: model);
        if (result.isEmpty) {
          return {
            'status': 'error',
            'message': 'Embedding returned empty vector'
          };
        }
        return {'status': 'ok', 'message': 'Embedding successful'};
      } catch (e) {
        return {'status': 'error', 'message': e.toString()};
      }
    });

    // 3. Update Model
    gateway.rpcRegistry.register('config.setModel', (params, context) async {
      final model = params?['model'] as String?;
      final provider = params?['provider'] as String?;
      if (model == null) {
        throw ProtocolError('Missing required parameter: model');
      }

      // Update vault primarily
      final config = await loadConfig(configPath);
      final current = await _loadAgentFromVault() ?? config.agent;
      final updated = current.copyWith(
        model: model,
        provider: provider ?? current.provider,
      );
      await _saveAgentToVault(updated);

      // Save to disk (stripping agent automatically)
      await saveConfig(config.copyWith(agent: updated), configPath);

      // Re-initialize config in Agent
      await _syncAgentManagerConfig();

      return {
        'status': 'ok',
        'model': model,
        'provider': provider ?? config.agent.provider,
      };
    });

    // 4. List Models for a provider
    gateway.rpcRegistry.register('config.listModels', (params, context) async {
      final provider = params?['provider'] as String?;
      String? apiKey = params?['apiKey'] as String?;

      if (provider == null) {
        throw ProtocolError('Missing required parameter: provider');
      }

      try {
        // If apiKey/baseUrl is empty, try to get it from storage
        String? baseUrl;
        final isLocal =
            provider == 'ollama' || provider == 'vllm' || provider == 'litellm';

        if (apiKey == null || apiKey.isEmpty) {
          final storageKey = _getStorageKey(provider);
          apiKey = await storage.get(storageKey);
          if (isLocal) {
            baseUrl = apiKey;
            apiKey =
                provider; // For local providers, api key is usually just their name
          }
        }

        if (apiKey == null || apiKey.isEmpty) {
          // Fallback to empty string for ProviderFactory but it might fail
          apiKey = isLocal ? provider : '';
        }

        final models = await ProviderFactory.listModels(
          provider: provider,
          apiKey: apiKey,
          baseUrl: baseUrl,
        );
        return {'status': 'ok', 'models': models};
      } catch (e) {
        return {'status': 'error', 'message': e.toString()};
      }
    });

    // 4b. List Models with details (capabilities)
    gateway.rpcRegistry.register('config.listModelsDetailed',
        (params, context) async {
      final provider = params?['provider'] as String?;
      String? apiKey = params?['apiKey'] as String?;

      if (provider == null) {
        throw ProtocolError('Missing required parameter: provider');
      }

      try {
        String? baseUrl;
        final isLocal =
            provider == 'ollama' || provider == 'vllm' || provider == 'litellm';

        if (apiKey == null || apiKey.isEmpty) {
          final storageKey = _getStorageKey(provider);
          apiKey = await storage.get(storageKey);
          if (isLocal) {
            baseUrl = apiKey;
            apiKey = provider;
          }
        }

        if (apiKey == null || apiKey.isEmpty) {
          apiKey = isLocal ? provider : '';
        }

        final models = await ProviderFactory.listModelsDetailed(
          provider: provider,
          apiKey: apiKey,
          storage: storage,
          baseUrl: baseUrl,
        );
        return {'status': 'ok', 'models': models};
      } catch (e) {
        return {'status': 'error', 'message': e.toString()};
      }
    });

    // 4c. Get capabilities for a specific model
    gateway.rpcRegistry.register('config.getModelCapabilities',
        (params, context) async {
      final provider = params?['provider'] as String?;
      final model = params?['model'] as String?;

      if (provider == null || model == null) {
        throw ProtocolError('Missing required parameters: provider, model');
      }

      try {
        final caps = await ProviderFactory.getModelCapabilities(
          model: model,
          provider: provider,
          storage: storage,
        );
        return {'status': 'ok', 'capabilities': caps.toJson()};
      } catch (e) {
        return {'status': 'error', 'message': e.toString()};
      }
    });

    // 5. Update User Config — stored encrypted in vault, NOT in ghost.json
    gateway.rpcRegistry.register('config.updateUser', (params, context) async {
      if (params == null) throw ProtocolError('Missing params');
      _log.info('Updating user config (vault): $params');

      // Load current user (from vault if available, else from JSON as fallback)
      final config = await loadConfig(configPath);
      final current = await _loadUserFromVault() ?? config.user;

      final updated = current.copyWith(
        name: params['name'] as String?,
        callSign: params['callSign'] as String?,
        pronouns: params['pronouns'] as String?,
        timezone: params['timezone'] as String?,
        language: params['language'] as String?,
        notes: params['notes'] as String?,
        avatar: params['avatar'] as String?,
      );

      await _saveUserToVault(updated);
      await _syncAgentManagerConfig();
      return {'status': 'ok', 'user': updated.toJson()};
    });

    // 6. Update Identity Config — stored encrypted in vault, NOT in ghost.json
    gateway.rpcRegistry.register('config.updateIdentity',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');
      _log.info('Updating identity config (vault): $params');

      // Load current identity (from vault if available, else from JSON as fallback)
      final config = await loadConfig(configPath);
      final current = await _loadIdentityFromVault() ?? config.identity;

      final updated = current.copyWith(
        name: params['name'] as String?,
        creature: params['creature'] as String?,
        vibe: params['vibe'] as String?,
        emoji: params['emoji'] as String?,
        notes: params['notes'] as String?,
        avatar: params['avatar'] as String?,
      );

      await _saveIdentityToVault(updated);
      await _syncAgentManagerConfig();
      return {'status': 'ok', 'identity': updated.toJson()};
    });

    // 7. Update Agent Config (e.g. workspace)
    gateway.rpcRegistry.register('config.updateAgent', (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);
      final skills = (params['skills'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();

      final current = await _loadAgentFromVault() ?? config.agent;
      final updated = current.copyWith(
        workspace: params['workspace'] as String?,
        model: params['model'] as String?,
        provider: params['provider'] as String?,
        maxTokens: (params['maxTokens'] as num?)?.toInt(),
        thinkingMode: params['thinkingMode'] as String?,
        skills: skills,
      );

      if (updated.provider.isEmpty || updated.model.isEmpty) {
        throw ProtocolError('Provider und Modell dürfen nicht leer sein.');
      }

      await _saveAgentToVault(updated);
      await saveConfig(config.copyWith(agent: updated), configPath);

      // Reload agent manager
      await _syncAgentManagerConfig();

      return {'status': 'ok'};
    });

    // 7a. Get Google OAuth credentials from vault
    gateway.rpcRegistry.register('config.getGoogleCredentials',
        (params, context) async {
      final clientIdWeb = await storage.get('google_client_id_web') ?? '';
      final clientIdDesktop =
          await storage.get('google_client_id_desktop') ?? '';
      final clientSecret = await storage.get('google_client_secret') ?? '';
      return {
        'clientIdWeb': clientIdWeb,
        'clientIdDesktop': clientIdDesktop,
        'clientSecret': clientSecret,
      };
    });

    // 7b. Update Integrations Config
    gateway.rpcRegistry.register('config.updateIntegrations',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);
      final updatedIntegrations = config.integrations.copyWith(
        googleClientIdWeb: params['googleClientIdWeb'] as String?,
        googleClientIdDesktop: params['googleClientIdDesktop'] as String?,
        googleClientSecret: params['googleClientSecret'] as String?,
        googleEmail: params['googleEmail'] as String?,
        googleDisplayName: params['googleDisplayName'] as String?,
        googlePhotoUrl: params['googlePhotoUrl'] as String?,
      );
      await _saveIntegrationsToVault(updatedIntegrations);
      await saveConfig(config, configPath);
      await _syncAgentManagerConfig();
      return {'status': 'ok', 'integrations': updatedIntegrations.toJson()};
    });

    // 7c. Update Channels Config
    gateway.rpcRegistry.register('config.updateChannels',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);

      final googleChatParams = params['googleChat'] as Map<String, dynamic>?;
      final telegramParams = params['telegram'] as Map<String, dynamic>?;

      if (telegramParams != null) {
        final settings = telegramParams['settings'] as Map<String, dynamic>?;
        final botToken = settings?['botToken'] as String?;
        if (botToken != null && botToken.isNotEmpty) {
          await storage.set('telegram_bot_token', botToken);
          _log.info('Updated telegram_bot_token in vault');
          // Remove from settings so it's not saved plain in config.json
          telegramParams['settings'] = Map<String, dynamic>.from(settings!)
            ..remove('botToken');
        }
      }

      final telegramEnabled = telegramParams?['enabled'] as bool? ??
          config.channels.telegram.enabled;

      if (!telegramEnabled) {
        await storage.remove('telegram_bot_token');
        _log.info('Cleared telegram_bot_token from vault (channel disabled)');
      }

      final updatedChannels = config.channels.copyWith(
        googleChat: googleChatParams != null
            ? ChannelConfig.fromJson(googleChatParams)
            : config.channels.googleChat,
        telegram: telegramParams != null
            ? ChannelConfig.fromJson(telegramParams)
            : config.channels.telegram,
      );

      await _saveChannelsToVault(updatedChannels);
      await saveConfig(config, configPath);

      // Reconnect telegram if updated
      if (telegramParams != null && updatedChannels.telegram.enabled) {
        final botName =
            updatedChannels.telegram.settings['botName'] as String? ??
                'GhostBot';
        await channelManager.updateTelegram(botName);
      }

      return {
        'status': 'ok',
        'channels': updatedChannels.toJson(),
        'channelStatus': channelManager.getStatus(),
      };
    });

    // 8. Custom Agent Management
    gateway.rpcRegistry.register('config.addCustomAgent',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);
      final agentData = params['agent'] as Map<String, dynamic>? ?? params;
      final newAgent = CustomAgentConfig.fromJson(agentData);

      final currentAgents =
          await _loadCustomAgentsFromVault() ?? config.customAgents;
      final updatedAgents = List<CustomAgentConfig>.from(currentAgents)
        ..add(newAgent);

      await _saveCustomAgentsToVault(updatedAgents);
      await saveConfig(
          config.copyWith(customAgents: updatedAgents), configPath);

      await _syncAgentManagerConfig();
      await agentManager.reloadCustomAgents(updatedAgents);

      return {'status': 'ok', 'agent': newAgent.toJson()};
    });

    gateway.rpcRegistry.register('config.updateCustomAgent',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);
      final agentData = params['agent'] as Map<String, dynamic>? ?? params;
      final updatedAgent = CustomAgentConfig.fromJson(agentData);

      final currentAgents =
          await _loadCustomAgentsFromVault() ?? config.customAgents;
      final updatedAgents = currentAgents
          .map((CustomAgentConfig a) =>
              a.id == updatedAgent.id ? updatedAgent : a)
          .toList();

      if (updatedAgent.provider == null ||
          updatedAgent.provider!.isEmpty ||
          updatedAgent.model == null ||
          updatedAgent.model!.isEmpty) {
        throw ProtocolError(
            'Provider und Modell für den Custom Agent dürfen nicht leer sein.');
      }

      await _saveCustomAgentsToVault(updatedAgents);
      await saveConfig(
          config.copyWith(customAgents: updatedAgents), configPath);

      await _syncAgentManagerConfig();
      await agentManager.reloadCustomAgents(updatedAgents);

      return {'status': 'ok', 'agent': updatedAgent.toJson()};
    });

    gateway.rpcRegistry.register('config.deleteCustomAgent',
        (params, context) async {
      final agentId = params?['id'] as String?;
      if (agentId == null) throw ProtocolError('Missing agent id');

      try {
        final avatarsBox = Hive.box<Uint8List>('avatars');
        await avatarsBox.delete('agent_avatar_$agentId');
      } catch (e) {
        _log.warning('Could not delete avatar for $agentId: $e');
      }

      final config = await loadConfig(configPath);
      final currentAgents =
          await _loadCustomAgentsFromVault() ?? config.customAgents;
      final updatedAgents = currentAgents
          .where((CustomAgentConfig a) => a.id != agentId)
          .toList();

      await _saveCustomAgentsToVault(updatedAgents);
      await saveConfig(
          config.copyWith(customAgents: updatedAgents), configPath);

      await _syncAgentManagerConfig();
      await agentManager.reloadCustomAgents(updatedAgents);

      return {'status': 'ok', 'deletedId': agentId};
    });

    // 9. Skills Management
    gateway.rpcRegistry.register('skills.list', (params, context) async {
      final skills = await agentManager.skillManager.loadSkills();
      return {'status': 'ok', 'skills': skills.map((s) => s.toJson()).toList()};
    });

    gateway.rpcRegistry.register('skills.install', (params, context) async {
      if (params == null) throw ProtocolError('Missing params');
      final zipBase64 = params['zip'] as String?;
      if (zipBase64 == null) throw ProtocolError('Missing zip base64 data');

      final zipBytes = base64Decode(zipBase64);
      final skill = await agentManager.skillManager.installSkill(zipBytes);
      // Wait to verify successful install, we could update the agents if there are globals
      // but the agents load skills dynamically for system prompt on the fly. Wait, Agent system prompt
      // is static once built. Let's rebuild agent prompts.
      await _syncAgentManagerConfig();
      gateway.broadcast('skills.changed');
      return {'status': 'ok', 'skill': skill.toJson()};
    });

    gateway.rpcRegistry.register('skills.downloadFromGithub',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');
      final url = params['url'] as String?;
      if (url == null) throw ProtocolError('Missing GitHub URL');

      final skill = await agentManager.skillManager.downloadGithubSkill(url);
      await _syncAgentManagerConfig();
      gateway.broadcast('skills.changed');
      return {'status': 'ok', 'skill': skill.toJson()};
    });

    gateway.rpcRegistry.register('skills.import', (params, context) async {
      if (params == null) throw ProtocolError('Missing params');
      final path = params['path'] as String?;
      if (path == null) throw ProtocolError('Missing path');

      final skill =
          await agentManager.skillManager.installSkillFromDirectory(path);
      await _syncAgentManagerConfig();
      gateway.broadcast('skills.changed');
      return {'status': 'ok', 'skill': skill.toJson()};
    });

    gateway.rpcRegistry.register('skills.delete', (params, context) async {
      final slug = params?['slug'] as String?;
      if (slug == null) throw ProtocolError('Missing slug');

      await agentManager.skillManager.deleteSkill(slug);
      await _syncAgentManagerConfig();
      gateway.broadcast('skills.changed');
      return {'status': 'ok', 'deletedSlug': slug};
    });

    gateway.rpcRegistry.register('skills.updateGlobal',
        (params, context) async {
      final slug = params?['slug'] as String?;
      final isGlobal = params?['isGlobal'] as bool?;
      if (slug == null || isGlobal == null) {
        throw ProtocolError('Missing slug or isGlobal');
      }

      await agentManager.skillManager.setGlobal(slug, isGlobal);
      await _syncAgentManagerConfig();
      gateway.broadcast('skills.changed');
      return {'status': 'ok', 'slug': slug, 'isGlobal': isGlobal};
    });

    gateway.rpcRegistry.register('skills.getMarkdown', (params, context) async {
      final slug = params?['slug'] as String?;
      if (slug == null) throw ProtocolError('Missing slug');

      final content = await agentManager.skillManager.readSkillContent(slug);
      return {'status': 'ok', 'slug': slug, 'content': content};
    });

    gateway.rpcRegistry.register('skills.updateMarkdown',
        (params, context) async {
      final slug = params?['slug'] as String?;
      final content = params?['content'] as String?;
      if (slug == null || content == null) {
        throw ProtocolError('Missing slug or content');
      }

      await agentManager.skillManager.updateSkillContent(slug, content);
      await _syncAgentManagerConfig();
      return {'status': 'ok', 'slug': slug};
    });

    gateway.rpcRegistry.register('skills.backup', (params, context) async {
      final data = await agentManager.skillManager.backupSkills();
      return {'status': 'ok', 'data': data};
    });

    gateway.rpcRegistry.register('skills.restore', (params, context) async {
      if (params == null) throw ProtocolError('Missing params');
      final data = params['data'] as String?;
      if (data == null) throw ProtocolError('Missing backup data');

      await agentManager.skillManager.restoreSkills(data);
      await _syncAgentManagerConfig();
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('channels.getErrors', (params, context) async {
      final errors = channelManager.connectionErrors.entries
          .map((e) => {
                'channelType': e.key,
                'message': e.value,
              })
          .toList();

      if (params?['clear'] == true) {
        final channelType = params?['channelType'] as String?;
        channelManager.clearConnectionErrors(channelType);
      }
      return {'status': 'ok', 'errors': errors};
    });

    // 16. Update memory config
    gateway.rpcRegistry.register('config.updateMemory',
        (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);
      final current = await _loadMemoryFromVault() ?? config.memory;

      final updated = MemoryConfig(
        enabled: params['enabled'] as bool? ?? current.enabled,
        ragEnabled: params['ragEnabled'] as bool? ?? current.ragEnabled,
        backend: params['backend'] as String? ?? current.backend,
        embeddingProvider:
            params['embeddingProvider'] as String? ?? current.embeddingProvider,
        embeddingModel:
            params['embeddingModel'] as String? ?? current.embeddingModel,
        chunkSize: (params['chunkSize'] as num?)?.toInt() ?? current.chunkSize,
        chunkOverlap:
            (params['chunkOverlap'] as num?)?.toInt() ?? current.chunkOverlap,
        vectorWeight: (params['vectorWeight'] as num?)?.toDouble() ??
            current.vectorWeight,
        bm25Weight:
            (params['bm25Weight'] as num?)?.toDouble() ?? current.bm25Weight,
      );

      await _saveMemoryToVault(updated);
      await saveConfig(config.copyWith(memory: updated), configPath);
      await _syncAgentManagerConfig();

      return {'status': 'ok'};
    });

    // 17. Clear memory
    gateway.rpcRegistry.register('config.clearMemory', (params, context) async {
      final type = params?['type'] as String?;
      if (type == null) throw ProtocolError('Missing required parameter: type');

      await agentManager.clearMemory(type);
      return {'status': 'ok'};
    });

    // 18. Update tools config
    gateway.rpcRegistry.register('config.updateTools', (params, context) async {
      if (params == null) throw ProtocolError('Missing params');

      final config = await loadConfig(configPath);
      final updatedTools = config.tools.copyWith(
        profile: params['profile'] as String?,
        allow: (params['allow'] as List<dynamic>?)?.cast<String>(),
        deny: (params['deny'] as List<dynamic>?)?.cast<String>(),
        browserHeadless: params['browserHeadless'] as bool?,
      );

      await _saveToolsToVault(updatedTools);
      await saveConfig(config, configPath);
      await _syncAgentManagerConfig();

      return {'status': 'ok'};
    });
  }

  Future<List<Map<String, String>>> _detectLocalProviders() async {
    final results = <Map<String, String>>[];
    final client = http.Client();

    final checks = {
      'ollama': 'http://localhost:11434/v1',
      'vllm': 'http://localhost:8000/v1',
      'litellm': 'http://localhost:4000/v1',
    };

    for (final entry in checks.entries) {
      try {
        final url = entry.value;
        final response = await client
            .get(Uri.parse('$url/models'))
            .timeout(const Duration(milliseconds: 500));
        if (response.statusCode == 200) {
          results.add({
            'id': entry.key,
            'url': url,
          });
        }
      } catch (_) {
        // Skip if not reachable
      }
    }
    client.close();
    return results;
  }

  String _getStorageKey(String service) {
    if (service == 'telegram') return 'telegram_bot_token';
    if (service == 'google_workspace') return 'google_access_token';
    if (service == 'google_client_id_web') return 'google_client_id_web';
    if (service == 'google_client_id_desktop') {
      return 'google_client_id_desktop';
    }
    if (service == 'google_client_secret') return 'google_client_secret';
    return '${service}_api_key';
  }

  // ---------------------------------------------------------------------------
  // Vault helpers for user + identity
  // ---------------------------------------------------------------------------

  static const _userVaultKey = 'user_config';
  static const _identityVaultKey = 'identity_config';
  static const _agentVaultKey = 'agent_config';
  static const _memoryVaultKey = 'memory_config';
  static const _customAgentsVaultKey = 'custom_agents_config';

  Future<UserConfig?> _loadUserFromVault() async {
    final raw = await storage.get(_userVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return UserConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse user_config from vault: $e');
      return null;
    }
  }

  Future<IdentityConfig?> _loadIdentityFromVault() async {
    final raw = await storage.get(_identityVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return IdentityConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse identity_config from vault: $e');
      return null;
    }
  }

  Future<void> _saveUserToVault(UserConfig user) async {
    await storage.set(_userVaultKey, jsonEncode(user.toJson()));
    _log.info('Saved user config to vault (encrypted)');
  }

  Future<void> _saveIdentityToVault(IdentityConfig identity) async {
    await storage.set(_identityVaultKey, jsonEncode(identity.toJson()));
    _log.info('Saved identity config to vault (encrypted)');
  }

  Future<AgentConfig?> _loadAgentFromVault() async {
    final raw = await storage.get(_agentVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AgentConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse agent_config from vault: $e');
      return null;
    }
  }

  Future<void> _saveAgentToVault(AgentConfig agent) async {
    await storage.set(_agentVaultKey, jsonEncode(agent.toJson()));
    _log.info('Saved agent config to vault (encrypted)');
  }

  Future<void> _saveMemoryToVault(MemoryConfig memory) async {
    await storage.set(_memoryVaultKey, jsonEncode(memory.toJson()));
    _log.info('Saved memory config to vault (encrypted)');
  }

  Future<MemoryConfig?> _loadMemoryFromVault() async {
    final raw = await storage.get(_memoryVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final memory = MemoryConfig.fromJson(json);
      // Self-heal: many users have "ghost" defaults from previous bugs.
      // 1. OpenAI default (text-embedding-3-small)
      // 2. OpenRouter default (nvidia/llama-nemotron-embed-vl-1b-v2:free)
      final isOpenAIDefault = memory.embeddingProvider == 'openai' &&
          memory.embeddingModel == 'text-embedding-3-small';
      final isOpenRouterDefault = memory.embeddingProvider == 'openrouter' &&
          memory.embeddingModel == 'nvidia/llama-nemotron-embed-vl-1b-v2:free';

      if ((isOpenAIDefault || isOpenRouterDefault) && !memory.ragEnabled) {
        _log.info(
            'Clearing "ghost" embedding defaults from vault (${memory.embeddingProvider})');
        final corrected = MemoryConfig(
          enabled: memory.enabled,
          ragEnabled: false,
          backend: memory.backend,
          embeddingProvider: '',
          embeddingModel: '',
          chunkSize: memory.chunkSize,
          chunkOverlap: memory.chunkOverlap,
          vectorWeight: memory.vectorWeight,
          bm25Weight: memory.bm25Weight,
        );
        // Save the correction back to vault so it doesn't happen every time
        await _saveMemoryToVault(corrected);
        return corrected;
      }
      return memory;
    } catch (e) {
      _log.warning('Failed to parse memory_config from vault: $e');
      return null;
    }
  }

  Future<void> _saveCustomAgentsToVault(List<CustomAgentConfig> agents) async {
    await storage.set(_customAgentsVaultKey,
        jsonEncode(agents.map((a) => a.toJson()).toList()));
    _log.info('Saved custom agents config to vault (encrypted)');
  }

  Future<List<CustomAgentConfig>?> _loadCustomAgentsFromVault() async {
    final raw = await storage.get(_customAgentsVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((a) => CustomAgentConfig.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log.warning('Failed to parse custom_agents_config from vault: $e');
      return null;
    }
  }

  /// Migrates existing plaintext user/identity from ghost.json to the
  /// vault on first access, then strips them from the JSON file.
  bool _migrationDone = false;
  Future<void> _migrateUserIdentityToVault() async {
    if (_migrationDone) return;
    _migrationDone = true;

    try {
      final config = await loadConfig(configPath);
      bool changed = false;

      // Migrate user if vault doesn't have it yet but JSON has non-default values
      if (await storage.get(_userVaultKey) == null) {
        final u = config.user;
        if (u.name.isNotEmpty || u.callSign.isNotEmpty || u.notes.isNotEmpty) {
          await _saveUserToVault(u);
          _log.info('Migrated user config from ghost.json to vault');
          changed = true;
        }
      }

      // Migrate identity if vault doesn't have it yet but JSON has non-default values
      if (await storage.get(_identityVaultKey) == null) {
        final i = config.identity;
        if (i.name != 'Ghost' || i.notes.isNotEmpty || i.avatar != null) {
          await _saveIdentityToVault(i);
          _log.info('Migrated identity config from ghost.json to vault');
          changed = true;
        }
      }

      // If we migrated anything, strip user+identity from the JSON file
      if (changed) {
        await _stripUserIdentityFromJson();
      }
    } catch (e) {
      _log.warning('Migration of user/identity to vault failed: $e');
    }
  }

  Future<void> _migrateAgentToVault() async {
    if (await storage.get(_agentVaultKey) != null) return;

    try {
      final config = await loadConfig(configPath);
      // We check if it has non-default values (at least model or provider)
      if (config.agent.model.isNotEmpty || config.agent.provider.isNotEmpty) {
        await _saveAgentToVault(config.agent);
        _log.info('Migrated agent config from ghost.json to vault');
        await _stripAgentFromJson();
      }
    } catch (e) {
      _log.warning('Migration of agent to vault failed: $e');
    }
  }

  Future<void> _migrateMemoryToVault() async {
    if (await storage.get(_memoryVaultKey) != null) return;

    try {
      final config = await loadConfig(configPath);
      // Only migrate if the JSON actually has a configured embedding provider.
      // If it's empty (default), do NOT write defaults to vault.
      if (config.memory.embeddingProvider.isNotEmpty ||
          config.memory.ragEnabled) {
        await _saveMemoryToVault(config.memory);
        _log.info('Migrated memory config from ghost.json to vault');
        await _stripMemoryFromJson();
      }
    } catch (e) {
      _log.warning('Migration of memory to vault failed: $e');
    }
  }

  Future<void> _migrateCustomAgentsToVault() async {
    if (await storage.get(_customAgentsVaultKey) != null) return;

    try {
      final config = await loadConfig(configPath);
      if (config.customAgents.isNotEmpty) {
        await _saveCustomAgentsToVault(config.customAgents);
        _log.info('Migrated custom agents from ghost.json to vault');
        await _stripCustomAgentsFromJson();
      }
    } catch (e) {
      _log.warning('Migration of custom agents to vault failed: $e');
    }
  }

  /// Removes user and identity sections from ghost.json in-place.
  Future<void> _stripUserIdentityFromJson() async {
    try {
      final file = File(configPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      raw.remove('user');
      raw.remove('identity');
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
      );
      _log.info('Stripped user+identity from ghost.json after vault migration');
    } catch (e) {
      _log.warning('Could not strip user/identity from JSON file: $e');
    }
  }

  /// Removes agent section from ghost.json in-place.
  Future<void> _stripAgentFromJson() async {
    try {
      final file = File(configPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      raw.remove('agent');
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
      );
      _log.info('Stripped agent from ghost.json');
    } catch (e) {
      _log.warning('Could not strip agent from JSON file: $e');
    }
  }

  /// Removes memory section from ghost.json in-place.
  Future<void> _stripMemoryFromJson() async {
    try {
      final file = File(configPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      raw.remove('memory');
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
      );
      _log.info('Stripped memory from ghost.json');
    } catch (e) {
      _log.warning('Could not strip memory from JSON file: $e');
    }
  }

  /// Removes customAgents section from ghost.json in-place.
  Future<void> _stripCustomAgentsFromJson() async {
    try {
      final file = File(configPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      raw.remove('customAgents');
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
      );
      _log.info('Stripped customAgents from ghost.json');
    } catch (e) {
      _log.warning('Could not strip customAgents from JSON file: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Vault helpers for channels, tools, session, integrations
  // ---------------------------------------------------------------------------

  static const _channelsVaultKey = 'channels_config';
  static const _toolsVaultKey = 'tools_config';
  static const _sessionVaultKey = 'session_config';
  static const _integrationsVaultKey = 'integrations_config';

  Future<ChannelsConfig?> _loadChannelsFromVault() async {
    final raw = await storage.get(_channelsVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ChannelsConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse channels_config from vault: $e');
      return null;
    }
  }

  Future<ToolsConfig?> _loadToolsFromVault() async {
    final raw = await storage.get(_toolsVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ToolsConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse tools_config from vault: $e');
      return null;
    }
  }

  Future<SessionConfig?> _loadSessionFromVault() async {
    final raw = await storage.get(_sessionVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SessionConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse session_config from vault: $e');
      return null;
    }
  }

  Future<IntegrationsConfig?> _loadIntegrationsFromVault() async {
    final raw = await storage.get(_integrationsVaultKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return IntegrationsConfig.fromJson(json);
    } catch (e) {
      _log.warning('Failed to parse integrations_config from vault: $e');
      return null;
    }
  }

  Future<void> _saveChannelsToVault(ChannelsConfig channels) async {
    await storage.set(_channelsVaultKey, jsonEncode(channels.toJson()));
    _log.info('Saved channels config to vault (encrypted)');
  }

  Future<void> _saveToolsToVault(ToolsConfig tools) async {
    await storage.set(_toolsVaultKey, jsonEncode(tools.toJson()));
    _log.info('Saved tools config to vault (encrypted)');
  }

  Future<void> _saveSessionToVault(SessionConfig session) async {
    await storage.set(_sessionVaultKey, jsonEncode(session.toJson()));
    _log.info('Saved session config to vault (encrypted)');
  }

  Future<void> _saveIntegrationsToVault(IntegrationsConfig integrations) async {
    await storage.set(_integrationsVaultKey, jsonEncode(integrations.toJson()));
    _log.info('Saved integrations config to vault (encrypted)');
  }

  Future<void> _migrateAdditionalConfigsToVault() async {
    try {
      final config = await loadConfig(configPath);

      if (await storage.get(_channelsVaultKey) == null) {
        await _saveChannelsToVault(config.channels);
        await _stripSectionFromJson('channels');
        _log.info('Migrated channels to vault');
      }
      if (await storage.get(_toolsVaultKey) == null) {
        await _saveToolsToVault(config.tools);
        await _stripSectionFromJson('tools');
        _log.info('Migrated tools to vault');
      }
      if (await storage.get(_sessionVaultKey) == null) {
        await _saveSessionToVault(config.session);
        await _stripSectionFromJson('session');
        _log.info('Migrated session to vault');
      }
      if (await storage.get(_integrationsVaultKey) == null) {
        await _saveIntegrationsToVault(config.integrations);
        await _stripSectionFromJson('integrations');
        _log.info('Migrated integrations to vault');
      }
    } catch (e) {
      _log.warning('Migration of additional configs to vault failed: $e');
    }
  }

  Future<void> _stripSectionFromJson(String section) async {
    try {
      final file = File(configPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      raw.remove(section);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
      );
      _log.info('Stripped $section from ghost.json');
    } catch (e) {
      _log.warning('Could not strip $section from JSON file: $e');
    }
  }

  /// Synchronizes the AgentManager with the latest consolidated configuration
  /// from disk (JSON) and the vault (encrypted).
  Future<void> _syncAgentManagerConfig() async {
    final diskConfig = await loadConfig(configPath);

    // Overlay everything from the vault
    final user = await _loadUserFromVault() ?? diskConfig.user;
    final identity = await _loadIdentityFromVault() ?? diskConfig.identity;
    final agent = await _loadAgentFromVault() ?? diskConfig.agent;
    final memory = await _loadMemoryFromVault() ?? diskConfig.memory;
    final customAgents =
        await _loadCustomAgentsFromVault() ?? diskConfig.customAgents;

    final channels = await _loadChannelsFromVault() ?? diskConfig.channels;
    final tools = await _loadToolsFromVault() ?? diskConfig.tools;
    final session = await _loadSessionFromVault() ?? diskConfig.session;
    final integrations =
        await _loadIntegrationsFromVault() ?? diskConfig.integrations;

    final consolidated = diskConfig.copyWith(
      user: user,
      identity: identity,
      agent: agent,
      memory: memory,
      customAgents: customAgents,
      channels: channels,
      tools: tools,
      session: session,
      integrations: integrations,
    );

    // Push the full consolidated config to the manager
    await agentManager.updateConfig(consolidated);
    agentManager.notifyConfigChanged();
    _log.info('AgentManager synchronized with consolidated configuration');
  }
}
