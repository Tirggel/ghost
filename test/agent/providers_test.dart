import 'package:test/test.dart';
import 'package:ghost/engine/agent/providers/factory.dart';
import 'package:ghost/engine/config/secure_storage.dart';
import 'package:ghost/engine/agent/providers/openai.dart';

void main() {
  late SecureStorage storage;

  setUp(() {
    storage = MemorySecureStorage();
  });

  group('ProviderFactory Resolution', () {
    test('Resolves Mistral correctly', () async {
      final provider = await ProviderFactory.create(
        model: 'mistral/mistral-large-latest',
        storage: storage,
      );
      expect(provider, isA<OpenAIProvider>());
      expect(provider.providerId, equals('mistral'));
      expect((provider as OpenAIProvider).baseUrl,
          equals('https://api.mistral.ai/v1'));
      expect(provider.modelId, equals('mistral-large-latest'));
    });

    test('Resolves Groq correctly', () async {
      final provider = await ProviderFactory.create(
        model: 'groq/llama-3.1-70b-versatile',
        storage: storage,
      );
      expect(provider.providerId, equals('groq'));
      expect((provider as OpenAIProvider).baseUrl,
          equals('https://api.groq.com/openai/v1'));
    });

    test('Resolves Together AI correctly', () async {
      final provider = await ProviderFactory.create(
        model: 'together/meta-llama/Llama-3-70b-chat-hf',
        storage: storage,
      );
      expect(provider.providerId, equals('together'));
      expect((provider as OpenAIProvider).baseUrl,
          equals('https://api.together.xyz/v1'));
    });

    test('Resolves Perplexity correctly', () async {
      final provider = await ProviderFactory.create(
        model: 'perplexity/llama-3-sonar-large-32k-online',
        storage: storage,
      );
      expect(provider.providerId, equals('perplexity'));
      expect((provider as OpenAIProvider).baseUrl,
          equals('https://api.perplexity.ai'));
    });

    test('Resolves X.AI (Grok) correctly', () async {
      final provider = await ProviderFactory.create(
        model: 'xai/grok-beta',
        storage: storage,
      );
      expect(provider.providerId, equals('xai'));
      expect(
          (provider as OpenAIProvider).baseUrl, equals('https://api.x.ai/v1'));
    });

    test('Resolves legacy grok prefix correctly', () async {
      final provider = await ProviderFactory.create(
        model: 'grok/grok-beta',
        storage: storage,
      );
      expect(provider.providerId, equals('xai'));
    });
  });
}
