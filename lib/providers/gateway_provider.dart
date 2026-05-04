import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/gateway.dart';
import '../core/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/models/chat_session.dart';
import '../core/models/config_models.dart';
export '../core/models/config_models.dart';
import '../core/internal_gateway.dart';
import '../core/secure_storage_impl.dart';
import '../core/platform_storage.dart';

// The URL of the gateway (defaulting to localhost)
final gatewayUrlProvider = AsyncNotifierProvider<GatewayUrlNotifier, String>(
  () {
    return GatewayUrlNotifier();
  },
);

class GatewayUrlNotifier extends AsyncNotifier<String> {
  static const _key = 'gateway_url';

  @override
  FutureOr<String> build() async {
    // 1. Check if internal gateway is active
    final gatewayManager = InternalGatewayManager();
    if (gatewayManager.isRunning) {
      final port = gatewayManager.port;
      if (port != null) {
        return 'ws://127.0.0.1:$port';
      }
    }

    // 2. Check SharedPreferences (manual override)
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_key);
    if (savedUrl != null) return savedUrl;

    // 3. Fallback to local config file discovery
    if (!kIsWeb) {
      try {
        final configPath = await PlatformStorage.getConfigPath();
        final configFile = File(configPath);
        if (await configFile.exists()) {
          final content = await configFile.readAsString();
          final json = jsonDecode(content);
          final port = json['gateway']?['port'];
          if (port != null) {
            final url = 'ws://127.0.0.1:$port';
            return url;
          }
        }
      } catch (_) {}
    }

    // Absolute fallback
    return AppConstants.defaultGatewayUrl;
  }

  Future<void> setUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, url);
    state = AsyncValue.data(url);
  }
}

/// Derives the HTTP base URL from the WebSocket URL.
/// e.g. ws://127.0.0.1:18789 -> http://127.0.0.1:18789
String _gatewayHttpUrl(String wsUrl) {
  return wsUrl
      .replaceFirst('wss://', 'https://')
      .replaceFirst('ws://', 'http://');
}

// The Auth token
final authTokenProvider = AsyncNotifierProvider<AuthTokenNotifier, String?>(() {
  return AuthTokenNotifier();
});

class AuthTokenNotifier extends AsyncNotifier<String?> {
  static const _tokenKey = 'auth_token';
  final _secureStorage = FlutterSecureStorageImpl();

  @override
  FutureOr<String?> build() async {
    // 1. Try secure storage first (preferred)
    final token = await _secureStorage.get(_tokenKey);
    if (token != null && token.isNotEmpty) {
      return token;
    }

    // 2. Fallback to gateway discovery (sync from host)
    final wsUrl = await ref.watch(gatewayUrlProvider.future);
    final baseUrl = _gatewayHttpUrl(wsUrl);
    try {
      final response = await http.get(Uri.parse('$baseUrl/client-token'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fetchedToken = data['token'] as String?;
        if (fetchedToken != null && fetchedToken.isNotEmpty) {
          // Persist securely
          await _secureStorage.set(_tokenKey, fetchedToken);
          return fetchedToken;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> setToken(String token) async {
    // Persist securely
    await _secureStorage.set(_tokenKey, token);

    // Sync to gateway
    final wsUrl = await ref.read(gatewayUrlProvider.future);
    final baseUrl = _gatewayHttpUrl(wsUrl);
    try {
      await http.post(
        Uri.parse('$baseUrl/client-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
    state = AsyncValue.data(token);
  }

  Future<void> logout() async {
    ref.read(gatewayClientProvider).disconnect();

    // Clear secure storage
    await _secureStorage.set(_tokenKey, '');
    await _secureStorage.remove(_tokenKey);

    // Clear gateway storage
    final wsUrl = await ref.read(gatewayUrlProvider.future);
    final baseUrl = _gatewayHttpUrl(wsUrl);
    try {
      await http.delete(Uri.parse('$baseUrl/client-token'));
    } catch (_) {}
    state = const AsyncValue.data(null);
  }

  /// Clears the local cached token AND the gateway-side client_token.
  /// Use this during a restore: the gateway is about to restart and will
  /// re-provision the correct token from the restored vault. We must also
  /// clear the server-side client_token so that if authTokenProvider.build()
  /// runs re-discovery (GET /client-token) before the gateway has restarted,
  /// it does NOT get back the stale old token.
  Future<void> clearLocalToken() async {
    await _secureStorage.set(_tokenKey, '');
    await _secureStorage.remove(_tokenKey);

    // Also wipe the server-side client_token. The gateway is still briefly
    // running (restore is deferred), so this HTTP call should succeed.
    final wsUrl = await ref.read(gatewayUrlProvider.future);
    final baseUrl = _gatewayHttpUrl(wsUrl);
    try {
      await http.delete(Uri.parse('$baseUrl/client-token'));
    } catch (_) {}

    state = const AsyncValue.data(null);
  }
}


// Global Gateway Client Instance
final gatewayClientProvider = Provider<GatewayClient>((ref) {
  final urlAsync = ref.watch(gatewayUrlProvider);
  // main.dart ensures we don't build children until gatewayUrlProvider has data,
  // so requireValue is safe here when the UI needs the client.
  final url = urlAsync.value ?? AppConstants.defaultGatewayUrl;
  final client = GatewayClient(url: url);
  ref.onDispose(() => client.dispose());
  return client;
});

// Connection status
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final client = ref.watch(gatewayClientProvider);
  return client.status;
});

// Session History list
final sessionsProvider = NotifierProvider<SessionsNotifier, List<ChatSession>>(
  () {
    return SessionsNotifier();
  },
);

class SessionsNotifier extends Notifier<List<ChatSession>> {
  final List<ChatSession> _pending = [];

  @override
  List<ChatSession> build() {
    // Auto-refresh when authenticated
    ref.listen(connectionStatusProvider, (prev, next) {
      if (next.value == ConnectionStatus.authenticated) {
        refresh();
      }
    });

    final sub = ref.read(gatewayClientProvider).messages.listen((msg) {
      if (msg['method'] == 'agent.session_updated') {
        final sessionId = msg['params']['sessionId'] as String?;
        final title = msg['params']['title'] as String?;
        if (sessionId != null && title != null) {
          state = state.map((s) {
            if (s.id == sessionId) {
              return ChatSession(
                id: s.id,
                title: title,
                model: s.model,
                provider: s.provider,
                messageCount: s.messageCount,
                agentName: s.agentName,
                agentId: s.agentId,
                createdAt: s.createdAt,
                lastActiveAt: s.lastActiveAt,
                inputTokens: s.inputTokens,
                outputTokens: s.outputTokens,
              );
            }
            return s;
          }).toList();

          // Also update pending if applicable
          _pending.removeWhere((p) => p.id == sessionId);
        }
      } else if (msg['method'] == 'agent.response' ||
          msg['method'] == 'agent.stream') {
        final sessionId = msg['params']['sessionId'] as String?;
        if (sessionId != null) {
          final exists =
              state.any((s) => s.id == sessionId) ||
              _pending.any((s) => s.id == sessionId);
          if (!exists) {
            refresh();
          }
        }
      }
    });
    ref.onDispose(() => sub.cancel());

    // Initial check
    final status = ref.read(connectionStatusProvider).value;
    if (status == ConnectionStatus.authenticated) {
      Future.microtask(() => refresh());
    }

    return [];
  }

  void addPendingSession(ChatSession session) {
    _pending.add(session);
    state = [...state, session];
  }

  Future<void> refresh() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('agent.sessions');
      final serverSessions = (result['sessions'] as List<dynamic>)
          .map((s) => ChatSession.fromJson(s as Map<String, dynamic>))
          .toList();

      // Remove from pending if present on server
      _pending.removeWhere((p) => serverSessions.any((s) => s.id == p.id));

      // Combine server + pending
      // Combine server + pending and sort by last active (newest first)
      final combined = [...serverSessions, ..._pending];

      // MERGE: Preserve local token counts if server has 0
      final updated = combined.map((s) {
        final existing = state.where((old) => old.id == s.id).firstOrNull;
        if (existing != null) {
          return ChatSession(
            id: s.id,
            title: s.title,
            model: s.model,
            provider: s.provider,
            messageCount: s.messageCount,
            agentName: s.agentName,
            agentId: s.agentId,
            createdAt: s.createdAt,
            lastActiveAt: s.lastActiveAt,
            inputTokens: s.inputTokens > 0
                ? s.inputTokens
                : existing.inputTokens,
            outputTokens: s.outputTokens > 0
                ? s.outputTokens
                : existing.outputTokens,
          );
        }
        return s;
      }).toList();

      updated.sort((a, b) {
        final dateA =
            a.lastActiveAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB =
            b.lastActiveAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA); // Newest first
      });
      state = updated;
    } catch (e) {
      // Refresh failed
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    _pending.removeWhere((s) => s.id == sessionId);
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('agent.deleteSession', {'sessionId': sessionId});
      state = state.where((s) => s.id != sessionId).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setSessionModel(
    String sessionId,
    String model,
    String? provider,
  ) async {
    final client = ref.read(gatewayClientProvider);

    // Update pending if applicable
    final pIndex = _pending.indexWhere((s) => s.id == sessionId);
    if (pIndex != -1) {
      final old = _pending[pIndex];
      _pending[pIndex] = ChatSession(
        id: old.id,
        title: old.title,
        model: model,
        provider: provider,
        messageCount: old.messageCount,
        agentName: old.agentName,
        agentId: old.agentId,
        createdAt: old.createdAt,
        lastActiveAt: old.lastActiveAt,
        inputTokens: old.inputTokens,
        outputTokens: old.outputTokens,
      );
    }

    try {
      await client.call('agent.setSessionModel', {
        'sessionId': sessionId,
        'model': model,
        'provider': provider,
      });
      // Update local state
      state = state.map((s) {
        if (s.id == sessionId) {
          return ChatSession(
            id: s.id,
            title: s.title,
            model: model,
            provider: provider,
            messageCount: s.messageCount,
            agentName: s.agentName,
            agentId: s.agentId,
            createdAt: s.createdAt,
            lastActiveAt: s.lastActiveAt,
            inputTokens: s.inputTokens,
            outputTokens: s.outputTokens,
          );
        }
        return s;
      }).toList();
    } catch (_) {}
  }

  Future<void> setSessionTitle(String sessionId, String title) async {
    final client = ref.read(gatewayClientProvider);

    // Update pending if applicable
    final pIndex = _pending.indexWhere((s) => s.id == sessionId);
    if (pIndex != -1) {
      final old = _pending[pIndex];
      _pending[pIndex] = ChatSession(
        id: old.id,
        title: title,
        model: old.model,
        provider: old.provider,
        messageCount: old.messageCount,
        agentName: old.agentName,
        agentId: old.agentId,
        createdAt: old.createdAt,
        lastActiveAt: old.lastActiveAt,
        inputTokens: old.inputTokens,
        outputTokens: old.outputTokens,
      );
    }

    try {
      await client.call('agent.setSessionTitle', {
        'sessionId': sessionId,
        'title': title,
      });
      // Update local state
      state = state.map((s) {
        if (s.id == sessionId) {
          return ChatSession(
            id: s.id,
            title: title,
            model: s.model,
            provider: s.provider,
            messageCount: s.messageCount,
            agentName: s.agentName,
            agentId: s.agentId,
            createdAt: s.createdAt,
            lastActiveAt: s.lastActiveAt,
            inputTokens: s.inputTokens,
            outputTokens: s.outputTokens,
          );
        }
        return s;
      }).toList();
    } catch (_) {}
  }

  void updateTokenUsage(String sessionId, int input, int output) {
    state = state.map((s) {
      if (s.id == sessionId) {
        return ChatSession(
          id: s.id,
          title: s.title,
          model: s.model,
          provider: s.provider,
          messageCount: s.messageCount,
          agentName: s.agentName,
          agentId: s.agentId,
          createdAt: s.createdAt,
          lastActiveAt: s.lastActiveAt,
          inputTokens: s.inputTokens + input,
          outputTokens: s.outputTokens + output,
        );
      }
      return s;
    }).toList();
  }
}

// Remote configuration state
final configProvider = NotifierProvider<ConfigNotifier, AppConfig>(() {
  return ConfigNotifier();
});

class ConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() {
    // Auto-refresh when authenticated
    ref.listen(connectionStatusProvider, (prev, next) {
      if (next.value == ConnectionStatus.authenticated) {
        refresh();
      }
    });

    // Initial check
    final status = ref.read(connectionStatusProvider).value;
    if (status == ConnectionStatus.authenticated) {
      Future.microtask(() => refresh());
    }

    // Listen for remote skill/config changes (e.g. from an agent import)
    final sub = ref.read(gatewayClientProvider).messages.listen((msg) {
      if (msg['method'] == 'skills.changed' ||
          msg['method'] == 'config.changed') {
        refresh();
      }
    });
    ref.onDispose(() => sub.cancel());

    return AppConfig.empty();
  }

  Future<void> refresh() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.get') as Map<String, dynamic>;
      state = AppConfig.fromJson(result);
    } catch (_) {}
  }

  Future<void> setModel(String model, {String? provider}) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.setModel', {
        'model': model,
        'provider': provider,
      });
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> getKey(String service) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.getKey', {'service': service});
      return result['key'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setKey(String service, String key) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.setKey', {'service': service, 'key': key});
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> testKey(String service, String key) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.testKey', {
        'service': service,
        'key': key,
      });
      return result as Map<String, dynamic>;
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> testEmbedding(
    String provider,
    String model,
  ) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.testEmbedding', {
        'provider': provider,
        'model': model,
      });
      return result as Map<String, dynamic>;
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<List<String>> listEmbeddingModels(String provider) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.listEmbeddingModels', {
        'provider': provider,
      });
      final List<dynamic> modelsList;
      if (result is Map && result.containsKey('models')) {
        modelsList = result['models'] as List<dynamic>;
      } else {
        modelsList = result as List<dynamic>;
      }
      return modelsList.cast<String>();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> listModels(String provider, String? apiKey) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.listModels', {
        'provider': provider,
        'apiKey': apiKey,
      });
      
      final List<dynamic> modelsList;
      if (result is Map && result.containsKey('models')) {
        modelsList = result['models'] as List<dynamic>;
      } else {
        modelsList = result as List<dynamic>;
      }
      final models = modelsList.cast<String>();
      models.sort((a, b) {
        final labelA = a.contains('/') ? a.split('/').last : a;
        final labelB = b.contains('/') ? b.split('/').last : b;
        return labelA.toLowerCase().compareTo(labelB.toLowerCase());
      });
      return models;
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> listModelsDetailed(
    String provider,
    String? apiKey,
  ) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.listModelsDetailed', {
        'provider': provider,
        'apiKey': apiKey,
      });
      if (result['status'] == 'ok') {
        final models = List<Map<String, dynamic>>.from(result['models'] as Iterable);
        return models;
      }
    } catch (_) {}
    return [];
  }

  Future<void> updateUser(Map<String, dynamic> userConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateUser', userConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateIdentity(Map<String, dynamic> identityConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateIdentity', identityConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateAgent(Map<String, dynamic> agentConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateAgent', agentConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateAgentSkills(List<String> skills) async {
    await updateAgent({'skills': skills});
  }

  Future<void> updateAgentWorkspace(String workspace) async {
    await updateAgent({'workspace': workspace});
  }

  Future<void> updateIntegrations(
    Map<String, dynamic> integrationsConfig,
  ) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateIntegrations', integrationsConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateMemory(Map<String, dynamic> memoryConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateMemory', memoryConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateChannels(Map<String, dynamic> channelsConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateChannels', channelsConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateTools(Map<String, dynamic> toolsConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateTools', toolsConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSecurity(Map<String, dynamic> securityConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateSecurity', securityConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addCustomAgent(Map<String, dynamic> agentConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.addCustomAgent', agentConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateCustomAgent(Map<String, dynamic> agentConfig) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.updateCustomAgent', agentConfig);
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<ModelCapabilities> getModelCapabilities(
    String provider,
    String model,
  ) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.getModelCapabilities', {
        'provider': provider,
        'model': model,
      });
      if (result['status'] == 'ok') {
        return ModelCapabilities.fromJson(
          result['capabilities'] as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return ModelCapabilities.textOnly();
  }

  Future<Map<String, dynamic>> getGoogleCredentials() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.getGoogleCredentials');
      return result as Map<String, dynamic>;
    } catch (e) {
      return {'clientIdWeb': '', 'clientIdDesktop': '', 'clientSecret': ''};
    }
  }

  Future<String?> getChannelToken(String channelId) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('config.getChannelToken', {
        'channelId': channelId,
      });
      return result['token'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getTelegramToken() async {
    return getChannelToken('telegram');
  }

  Future<void> deleteCustomAgent(String agentId) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('config.deleteCustomAgent', {'id': agentId});
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  // --- Skills ---

  Future<List<dynamic>> listSkills() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('skills.list');
      return result['skills'] as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  Future<void> installSkill(String zipBase64) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('skills.install', {'zip': zipBase64});
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> downloadSkillFromGithub(String url) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('skills.downloadFromGithub', {'url': url});
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteSkill(String slug) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('skills.delete', {'slug': slug});
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSkillGlobal(String slug, bool isGlobal) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('skills.updateGlobal', {
        'slug': slug,
        'isGlobal': isGlobal,
      });
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<String> getSkillMarkdown(String slug) async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('skills.getMarkdown', {'slug': slug});
      return result['content'] as String;
    } catch (_) {
      return '';
    }
  }

  Future<void> updateSkillMarkdown(String slug, String content) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('skills.updateMarkdown', {
        'slug': slug,
        'content': content,
      });
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> backupSkills() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final result = await client.call('skills.backup');
      return result['data'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> restoreSkills(String data) async {
    final client = ref.read(gatewayClientProvider);
    try {
      await client.call('skills.restore', {'data': data});
      await refresh();
    } catch (e) {
      rethrow;
    }
  }

  // --- Avatar Upload ---

  Future<String?> uploadAvatar(
    String name,
    List<int> bytes,
    String wsUrl,
  ) async {
    final baseUrl = _gatewayHttpUrl(wsUrl);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/upload?name=${Uri.encodeComponent(name)}'),
        body: bytes,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['path'] as String?;
      }
    } catch (_) {}
    return null;
  }
}

// -----------------------------------------------------------------------------
// Gateway Logs — Shared in-memory buffer for the Gateway console
// -----------------------------------------------------------------------------

class GatewayLogEntry {

  GatewayLogEntry({
    required this.level,
    required this.message,
    required this.time,
    this.logger,
  });

  factory GatewayLogEntry.fromJson(Map<String, dynamic> json) {
    return GatewayLogEntry(
      level: json['level'] as String? ?? 'INFO',
      message: json['message'] as String? ?? '',
      time: json['time'] != null
          ? DateTime.tryParse(json['time'] as String) ?? DateTime.now()
          : DateTime.now(),
      logger: json['logger'] as String?,
    );
  }
  final String level;
  final String message;
  final DateTime time;
  final String? logger;
}

final gatewayLogsProvider =
    NotifierProvider<GatewayLogsNotifier, List<GatewayLogEntry>>(() {
      return GatewayLogsNotifier();
    });

class GatewayLogsNotifier extends Notifier<List<GatewayLogEntry>> {
  static const int _maxLogs = 500;

  @override
  List<GatewayLogEntry> build() {
    final client = ref.watch(gatewayClientProvider);

    // Initial state is empty if client changes, but we might want to keep history?
    // For now, clean start on client change to avoid mixing logs from different gateways.

    final sub = client.messages.listen((msg) {
      if (msg['method'] == 'gateway.log') {
        final params = msg['params'];
        if (params != null) {
          final entry = GatewayLogEntry.fromJson(
            params as Map<String, dynamic>,
          );
          final next = [...state, entry];
          state = (next.length > _maxLogs)
              ? next.sublist(next.length - _maxLogs)
              : next;
        }
      }
    });

    ref.onDispose(() => sub.cancel());
    return [];
  }

  void clear() => state = [];
}

final skillsProvider = FutureProvider<List<dynamic>>((ref) async {
  // Listen to configProvider to refresh skills when config changes (e.g. after install/delete)
  ref.watch(configProvider);
  return ref.read(configProvider.notifier).listSkills();
});

final currentModelCapabilitiesProvider = FutureProvider<ModelCapabilities>((
  ref,
) async {
  final config = ref.watch(configProvider);
  final provider = config.agent.provider;
  final model = config.agent.model;

  if (provider == null || model == null || provider.isEmpty || model.isEmpty) {
    return ModelCapabilities.textOnly();
  }

  // Also listen for connection status to refetch if we just reconnected
  final status = ref.watch(connectionStatusProvider).value;
  if (status != ConnectionStatus.authenticated) {
    return ModelCapabilities.textOnly();
  }

  return ref
      .read(configProvider.notifier)
      .getModelCapabilities(provider, model);
});
