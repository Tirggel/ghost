import 'dart:async';
import 'package:logging/logging.dart';

import '../config/secure_storage.dart';
import 'registry.dart';

final _log = Logger('Ghost.Tools.Vault');

/// Tools for interacting with the secure vault.
class VaultTools {
  static void registerAll(ToolRegistry registry, SecureStorage storage) {
    registry.register(StoreApiKeyTool(storage));
  }
}

/// Tool to securely store an API key.
class StoreApiKeyTool extends Tool {
  StoreApiKeyTool(this.storage);

  final SecureStorage storage;

  @override
  String get name => 'store_api_key';

  @override
  String get description =>
      'Stores an API key securely in the Ghost vault under external services. '
      'Use this when the user asks you to save an API key for a specific service or provider.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'serviceName': {
            'type': 'string',
            'description': 'The name of the service (e.g. "coingecko"). Will be normalized to lowercase.',
          },
          'apiKey': {
            'type': 'string',
            'description': 'The API key or token to store.',
          },
        },
        'required': ['serviceName', 'apiKey'],
      };

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final serviceName = input['serviceName'] as String;
    final apiKey = input['apiKey'] as String;

    final serviceId = serviceName.trim().toLowerCase().replaceAll(' ', '_');
    final vaultKey = serviceId.endsWith('_api_key') ? serviceId : '${serviceId}_api_key';

    try {
      await storage.set(vaultKey, apiKey);
      _log.info('Stored API key for $serviceId via agent tool.');
      return ToolResult(
        output: 'Successfully stored API key for service "$serviceName" securely. '
            'It is now available in Settings > External Services.',
      );
    } catch (e) {
      return ToolResult.error('Failed to store API key: $e');
    }
  }
}
