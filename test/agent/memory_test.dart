import 'package:test/test.dart';
import 'package:ghost/engine/agent/memory.dart';
import 'package:ghost/engine/models/provider.dart';
import 'package:ghost/engine/models/message.dart';
import 'package:ghost/engine/config/config.dart';
import 'package:ghost/engine/config/secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'dart:io';

class MockEmbeddingProvider implements AIModelProvider {
  @override
  String get providerId => 'mock';
  @override
  String get modelId => 'mock-embedding';
  @override
  String get displayName => 'Mock Embedding';

  @override
  ModelCapabilities get capabilities => ModelCapabilities.textOnly();

  @override
  bool get supportsChat => true;

  @override
  Future<AIResponse> chat({
    required List<Message> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    double temperature = 0.7,
    List<ToolDefinition>? tools,
  }) async =>
      const AIResponse(content: '');

  @override
  Future<List<double>> embed(String text, {String? model}) async {
    // Generate deterministic mock vector based on text
    return [
      text.contains('Hund') || text.contains('Bello') ? 1.0 : 0.0,
      text.contains('Katze') || text.contains('Luna') ? 1.0 : 0.0,
      text.contains('Apple') ? 1.0 : 0.0,
      text.contains('Dart') ? 1.0 : 0.0,
      text.contains('Max') || text.contains('ich') ? 1.0 : 0.0,
    ];
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> testConnection() async {}
}

void main() {
  late Directory tempDir;
  late MemoryEngine memoryEngine;
  late SecureStorage storage;
  late MockEmbeddingProvider mockProvider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_memory_test_');
    Hive.init(tempDir.path);
    storage = MemorySecureStorage();
    mockProvider = MockEmbeddingProvider();
    memoryEngine = MemoryEngine(
      config: const MemoryConfig(enabled: true, backend: 'hive'),
      storage: storage,
      stateDir: tempDir.path,
    );
    await memoryEngine.initialize(testProvider: mockProvider);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MemoryEngine Integration', () {
    test('Add and Query memories', () async {
      await memoryEngine.add('Mein Hund heißt Bello.');
      await memoryEngine.add('Ich habe eine Katze namens Luna.');

      final results1 = await memoryEngine.query('Wie heißt mein Hund?');
      expect(results1, hasLength(greaterThan(0)));
      expect(results1.first, contains('Hund'));
      expect(results1.first, contains('Bello'));

      final resultsPunctuation = await memoryEngine.query('Hund?');
      expect(resultsPunctuation, hasLength(greaterThan(0)));
      expect(resultsPunctuation.first, contains('Bello'));

      final results2 = await memoryEngine.query('Erzähl mir von der Katze');
      expect(results2, hasLength(greaterThan(0)));
      expect(results2.first, contains('Katze'));
      expect(results2.first, contains('Luna'));

      final resultsEmpty =
          await memoryEngine.query('Was ist der Sinn des Lebens?');
      // Should not find anything highly relevant with our mock vectors
      expect(resultsEmpty, isEmpty);
    });

    test('Category-specific query', () async {
      await memoryEngine.add('User likes Apple Pie',
          metadata: {'category': 'user_preference'});
      await memoryEngine
          .add('Project uses Dart', metadata: {'category': 'project_info'});

      final prefResults =
          await memoryEngine.query('Apple', category: 'user_preference');
      expect(prefResults, hasLength(1));
      expect(prefResults.first, contains('Apple Pie'));

      final projResults =
          await memoryEngine.query('Apple', category: 'project_info');
      expect(projResults, isEmpty);
    });

    test('Personal profile retrieval via pronouns', () async {
      await memoryEngine
          .add('Ich heiße Max.', metadata: {'category': 'user_profile'});
      await memoryEngine
          .add('The sun is a star.', metadata: {'category': 'general_facts'});

      // Query with "ich" should find the profile info even if no direct match
      final results = await memoryEngine.query('Wer bin ich?');
      expect(results, isNotEmpty);
      expect(results.first, contains('Max'));
    });

    test('Add long text and retrieve chunks', () async {
      final longText = 'A' * 2000; // Will be split into at least 2 chunks
      await memoryEngine.add(longText);

      final results = await memoryEngine.query('A');
      expect(results, isNotEmpty);
      expect(results.first.length, lessThan(2000));
    });
  });
}
