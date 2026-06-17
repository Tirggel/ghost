import 'package:test/test.dart';
import 'package:ghost/engine/agent/agent.dart';
import 'package:ghost/engine/models/message.dart';
import 'package:ghost/engine/models/provider.dart';
import 'package:ghost/engine/sessions/manager.dart';
import 'package:ghost/engine/sessions/store.dart';
import 'package:ghost/engine/tools/registry.dart';
import 'package:ghost/engine/config/secure_storage.dart';
import 'package:ghost/engine/config/config.dart';
import 'package:ghost/engine/agent/memory.dart';
import 'package:ghost/engine/agent/rag_memory.dart';
import 'package:ghost/engine/agent/memory_system.dart';
import 'package:hive_ce/hive.dart';
import 'dart:io';
import 'dart:typed_data';

/// Mock provider for testing the agent loop.
class MockProvider implements AIModelProvider {
  MockProvider({this.responses = const []});

  final List<AIResponse> responses;
  int _callCount = 0;
  final List<List<Message>> capturedMessages = [];

  @override
  String get providerId => 'mock';
  @override
  String get modelId => 'mock-model';
  @override
  String get displayName => 'Mock Provider';

  @override
  ModelCapabilities get capabilities => ModelCapabilities.all();

  @override
  bool get supportsChat => true;

  @override
  Future<AIResponse> chat({
    required List<Message> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    double temperature = 0.7,
    List<ToolDefinition>? tools,
  }) async {
    capturedMessages.add(List<Message>.from(messages));
    if (_callCount >= responses.length) {
      return const AIResponse(content: 'Final mock response');
    }
    return responses[_callCount++];
  }

  @override
  Future<List<double>> embed(String text, {String? model}) async => [0.1, 0.2, 0.3];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> testConnection() async {}
}

void main() {
  late Directory tempDir;
  late SessionManager sessionManager;
  late ToolRegistry toolRegistry;
  late SecureStorage storage;
  late MemoryEngine memoryEngine;
  late RAGMemoryEngine ragMemoryEngine;
  late MemorySystem memorySystem;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_agent_test_');
    Hive.init(tempDir.path);
    sessionManager =
        SessionManager(store: SessionStore(encryptionKey: Uint8List(32)));
    toolRegistry = ToolRegistry();
    storage = MemorySecureStorage();
    memoryEngine = MemoryEngine(
      config: const MemoryConfig(enabled: false),
      storage: storage,
      stateDir: tempDir.path,
    );
    ragMemoryEngine = RAGMemoryEngine(
      config: const MemoryConfig(enabled: false),
      storage: storage,
      stateDir: tempDir.path,
    );
    memorySystem = MemorySystem(standard: memoryEngine, rag: ragMemoryEngine);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('Agent Runtime', () {
    test('Process simple message without tools', () async {
      final provider = MockProvider(responses: [
        const AIResponse(content: 'Hello! I am mock agent.'),
      ]);

      final agent = Agent(
        id: 'test-agent',
        provider: provider,
        sessionManager: sessionManager,
        toolRegistry: toolRegistry,
        storage: storage,
        memory: memorySystem,
      );

      await sessionManager.addMessage(
        sessionId: 's1',
        role: 'user',
        content: 'test message',
      );
      await agent.processMessage(sessionId: 's1', content: 'test message');

      final history = await sessionManager.getHistory('s1');
      expect(history.last.role, equals('assistant'));
      expect(history.last.content, equals('Hello! I am mock agent.'));
    });

    test('Process message with tool call iteration', () async {
      // 1. Model requests a tool
      // 2. Model receives tool result and gives final answer
      final provider = MockProvider(responses: [
        const AIResponse(content: 'Let me check the time.', toolCalls: [
          ToolCall(id: 'call_1', name: 'get_time', arguments: {})
        ]),
        const AIResponse(content: 'The time is 12:00.'),
      ]);

      // Simple mock tool
      final mockTool = _MockTool('get_time', '12:00');
      toolRegistry.register(mockTool);

      final agent = Agent(
        id: 'test-agent',
        provider: provider,
        sessionManager: sessionManager,
        toolRegistry: toolRegistry,
        storage: storage,
        memory: memorySystem,
      );

      await sessionManager.addMessage(
        sessionId: 's2',
        role: 'user',
        content: 'What time is it?',
      );
      await agent.processMessage(sessionId: 's2', content: 'What time is it?');

      final history = await sessionManager.getHistory('s2');
      expect(history.last.content, equals('Let me check the time.The time is 12:00.'));
      expect(mockTool.called, isTrue);

      // Verify focus marker retention on the user request message
      // 1st iteration message list: should have 1 message (user request with focus marker)
      expect(provider.capturedMessages.length, equals(2));
      expect(provider.capturedMessages[0].length, equals(1));
      expect(provider.capturedMessages[0][0].role, equals('user'));
      expect(provider.capturedMessages[0][0].content, contains('### ACTIVE REQUEST'));

      // 2nd iteration message list: should have 3 messages (user, assistant tool_call, tool result)
      // The user request (at index 0) must retain the ### ACTIVE REQUEST focus marker!
      expect(provider.capturedMessages[1].length, equals(3));
      expect(provider.capturedMessages[1][0].role, equals('user'));
      expect(provider.capturedMessages[1][0].content, contains('### ACTIVE REQUEST'));
    });
  });
}

class _MockTool extends Tool {
  _MockTool(this.name, this.result);
  @override
  final String name;
  final String result;
  @override
  String get description => 'Mock tool';
  @override
  Map<String, dynamic> get inputSchema => {'type': 'object'};
  bool called = false;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    called = true;
    return ToolResult(output: result);
  }
}
