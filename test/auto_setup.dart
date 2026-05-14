import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// A script to automatically fill the Ghost setup wizard data via JSON-RPC.
/// This allows developers to skip the setup wizard during development.
/// 
/// Usage: dart test/auto_setup.dart [gateway_url]
void main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args[0] : 'http://127.0.0.1:3000';
  final httpUrl = baseUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
  
  print('👻 Ghost Auto-Setup');
  print('Connecting to gateway at $baseUrl...');

  try {
    // 0. Fetch client token for authentication
    String? token;
    try {
      final tokenRes = await http.get(Uri.parse('$httpUrl/client-token'));
      if (tokenRes.statusCode == 200) {
        final data = jsonDecode(tokenRes.body);
        token = data['token'];
        if (token != null) {
          print('Fetched client token from gateway.');
        }
      }
    } catch (e) {
      print('Could not fetch token (might not be required): $e');
    }

    // 1. Login if token is available
    if (token != null) {
      print('Logging in...');
      await callRpc(baseUrl, 'auth.login', {'token': token});
      print('Authenticated successfully.');
    }

    // 2. Get initial config and detected providers
    final configRes = await callRpc(baseUrl, 'config.get');
    final detected = configRes['detectedLocalProviders'] as List<dynamic>? ?? [];
    
    print('Detected local providers: ${detected.map((p) => p['id']).toList()}');

    String provider = 'ollama';
    String? apiKey = 'http://localhost:11434';
    String? model;

    final ollama = detected.firstWhere((p) => p['id'] == 'ollama', orElse: () => null);
    if (ollama != null) {
      provider = 'ollama';
      apiKey = ollama['url'];
      print('Using detected Ollama at $apiKey');
    } else if (detected.isNotEmpty) {
      provider = detected.first['id'];
      apiKey = detected.first['url'];
      print('Using detected $provider at $apiKey');
    } else {
      print('No local providers detected. Falling back to default Ollama config.');
    }

    // 2. Try to fetch models for the provider
    print('Fetching models for $provider...');
    try {
      final modelsRes = await callRpc(baseUrl, 'config.listModels', {
        'provider': provider,
        'apiKey': apiKey,
      });
      final models = modelsRes['models'] as List<dynamic>? ?? [];
      if (models.isNotEmpty) {
        model = models.first.toString();
        print('Found models: $models. Selecting "$model"');
      } else {
        print('No models found for $provider.');
      }
    } catch (e) {
      print('Failed to list models: $e');
    }

    // Default model if none found
    model ??= 'llama3';

    // 3. Set API Key / Base URL
    print('Setting key for $provider...');
    await callRpc(baseUrl, 'config.setKey', {
      'service': provider,
      'key': apiKey,
    });

    // 4. Set Model
    print('Setting active model to $model...');
    await callRpc(baseUrl, 'config.setModel', {
      'model': model,
      'provider': provider,
    });

    // 5. Update User Profile
    print('Updating user profile...');
    await callRpc(baseUrl, 'config.updateUser', {
      'name': 'Developer',
      'callSign': 'Dev',
      'pronouns': 'They/Them',
      'language': 'en',
      'notes': 'Automated development user.',
    });

    // 6. Update Identity
    print('Updating agent identity...');
    await callRpc(baseUrl, 'config.updateIdentity', {
      'name': 'Ghost',
      'creature': 'Digital Ghost',
      'vibe': 'Friendly, analytical, and helpful',
      'emoji': '👻',
      'notes': 'Highly competent AI coworker.',
    });

    print('\n✅ Setup complete! You can now restart the app or refresh the UI.');
    exit(0);
  } catch (e) {
    print('\n❌ Error during auto-setup: $e');
    print('Make sure the Ghost gateway is running.');
    exit(1);
  }
}

Future<Map<String, dynamic>> callRpc(String baseUrl, String method, [Map<String, dynamic>? params]) async {
  final response = await http.post(
    Uri.parse(baseUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'method': method,
      'params': params,
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('HTTP Error: ${response.statusCode}\n${response.body}');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (data.containsKey('error')) {
    throw Exception('RPC Error: ${data['error']}');
  }

  return data['result'] as Map<String, dynamic>;
}
