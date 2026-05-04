import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../../config/secure_storage.dart';
import '../../infra/errors.dart';
import '../../models/provider.dart';
import '../../infra/env.dart';
import 'anthropic.dart';
import 'openai.dart';
import 'gemini.dart';

final _log = Logger('Ghost.ProviderFactory');

class ProviderFactory {
  // ---------------------------------------------------------------------------
  // Helper: Is this clearly a native Anthropic (Claude) model?
  // ---------------------------------------------------------------------------
  static bool _isAnthropicModel(String model) =>
      model.startsWith('claude-') ||
      RegExp(r'^(anthropic|claude)/').hasMatch(model);

  // ---------------------------------------------------------------------------
  // Helper: Is this clearly a native Google (Gemini) model?
  // ---------------------------------------------------------------------------
  static bool _isGoogleModel(String model) =>
      model.startsWith('gemini-') || model.startsWith('models/gemini');

  // ---------------------------------------------------------------------------
  // Helper: Is this clearly a DeepSeek model?
  // ---------------------------------------------------------------------------
  static bool _isDeepSeekModel(String model) =>
      model.toLowerCase().contains('deepseek');

  // ---------------------------------------------------------------------------
  // Helper: Is this an OpenRouter-style model? (org/model or org/model:tag,
  // where org is NOT a native provider we already support directly.)
  // ---------------------------------------------------------------------------
  static bool _isOpenRouterModel(String model) {
    if (!model.contains('/')) return false;
    if (_isAnthropicModel(model) ||
        _isGoogleModel(model) ||
        _isDeepSeekModel(model) ||
        model.startsWith('mistral/') ||
        model.startsWith('groq/') ||
        model.startsWith('together/') ||
        model.startsWith('moonshot/') ||
        model.startsWith('kimi-coding/') ||
        model.startsWith('nvidia/') ||
        model.startsWith('zai/') ||
        model.startsWith('huggingface/') ||
        model.startsWith('hf/') ||
        model.startsWith('minimax/') ||
        model.startsWith('qwen/') ||
        model.startsWith('xiaomi/') ||
        model.startsWith('ollama/') ||
        model.startsWith('ipex-llm/') ||
        model.startsWith('vllm/') ||
        model.startsWith('litellm/') ||
        model.startsWith('openai/') ||
        model.startsWith('vercel-ai-gateway/')) {
      return false;
    }
    // Looks like "arcee-ai/trinity-large-preview:free" etc.
    return true;
  }

  // ---------------------------------------------------------------------------
  // Resolve the effective provider, validating the hint against the model name.
  // If the hint conflicts with the model (e.g. provider=anthropic but model is
  // an OpenRouter model), we infer from the model name instead.
  // ---------------------------------------------------------------------------
  static String _resolveProvider(String model, String? hint) {
    final resolved = _doResolve(model, hint);
    _log.fine('Resolved provider for "$model" (hint: $hint) -> $resolved');
    return resolved;
  }

  static String _doResolve(String model, String? hint) {
    // If no hint, infer entirely from model name.
    // We treat empty string as no hint.
    if (hint == null || hint.isEmpty) {
      if (_isAnthropicModel(model)) return 'anthropic';
      if (_isGoogleModel(model)) return 'google';
      if (_isDeepSeekModel(model)) return 'deepseek';
      if (model.startsWith('mistral/')) return 'mistral';
      if (model.startsWith('groq/')) return 'groq';
      if (model.startsWith('together/')) return 'together';
      if (model.startsWith('perplexity/')) return 'perplexity';
      if (model.startsWith('xai/') || model.startsWith('grok/')) return 'xai';
      if (model.startsWith('moonshot/') || model.startsWith('kimi-coding/')) {
        return 'moonshot';
      }
      if (model.startsWith('nvidia/')) return 'nvidia';
      if (model.startsWith('zai/')) return 'zai';
      if (model.startsWith('hf/') || model.startsWith('huggingface/')) {
        return 'huggingface';
      }
      if (model.startsWith('minimax/')) return 'minimax';
      if (model.startsWith('qwen/')) return 'qwen';
      if (model.startsWith('xiaomi/')) return 'xiaomi';
      if (model.startsWith('vercel-ai-gateway/')) return 'vercel-ai-gateway';
      if (_isOpenRouterModel(model)) return 'openrouter';
      return 'openai';
    }

    // Hint given — validate it is consistent with the model
    switch (hint) {
      case 'anthropic':
        return _isAnthropicModel(model)
            ? 'anthropic'
            : _resolveProvider(model, null);
      case 'google':
        return _isGoogleModel(model) ? 'google' : _resolveProvider(model, null);
      case 'deepseek':
        return _isDeepSeekModel(model)
            ? 'deepseek'
            : _resolveProvider(model, null);
      case 'ollama':
      case 'ipex-llm':
      case 'vllm':
      case 'litellm':
        return hint;
      // openai, openrouter are generic routers — always trust them
      default:
        return hint;
    }
  }

  static String _normalizeUrl(String url, String defaultUrl) {
    String effective = url.isNotEmpty ? url : defaultUrl;
    if (!effective.contains('/v1')) {
      effective = effective.endsWith('/') ? '${effective}v1' : '$effective/v1';
    }
    // Remove trailing slash if present after /v1
    if (effective.endsWith('/')) {
      effective = effective.substring(0, effective.length - 1);
    }
    return effective;
  }

  static Future<AIModelProvider> create({
    required String model,
    String? provider,
    required SecureStorage storage,
  }) async {
    final resolved = _resolveProvider(model, provider);
    _log.fine('Creating provider: $resolved for model: $model');

    switch (resolved) {
      case 'anthropic':
        final apiKey = await storage.get('anthropic_api_key') ??
            Env.get('ANTHROPIC_API_KEY') ??
            '';
        return AnthropicProvider(apiKey: apiKey, model: model);

      case 'google':
        final apiKey = await storage.get('google_api_key') ??
            Env.get('GOOGLE_API_KEY') ??
            '';
        return GeminiProvider(apiKey: apiKey, model: model);

      case 'deepseek':
        final apiKey = await storage.get('deepseek_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model,
          baseUrl: 'https://api.deepseek.com',
          displayName: 'DeepSeek',
          providerId: 'deepseek',
          isReasoningModel:
              model.contains('reasoner') ||
              model.contains('thinking') ||
              model.contains('v4'),
        );

      case 'openrouter':
        final apiKey = await storage.get('openrouter_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model,
          baseUrl: 'https://openrouter.ai/api/v1',
          displayName: 'OpenRouter',
          providerId: 'openrouter',
        );

      case 'mistral':
        final apiKey = await storage.get('mistral_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('mistral/', ''),
          baseUrl: 'https://api.mistral.ai/v1',
          displayName: 'Mistral',
          providerId: 'mistral',
        );

      case 'groq':
        final apiKey = await storage.get('groq_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('groq/', ''),
          baseUrl: 'https://api.groq.com/openai/v1',
          displayName: 'Groq',
          providerId: 'groq',
        );

      case 'together':
        final apiKey = await storage.get('together_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('together/', ''),
          baseUrl: 'https://api.together.xyz/v1',
          displayName: 'Together AI',
          providerId: 'together',
        );

      case 'perplexity':
        final apiKey = await storage.get('perplexity_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('perplexity/', ''),
          baseUrl: 'https://api.perplexity.ai',
          displayName: 'Perplexity',
          providerId: 'perplexity',
        );

      case 'xai':
        final apiKey = await storage.get('xai_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst(RegExp(r'^(xai|grok)/'), ''),
          baseUrl: 'https://api.x.ai/v1',
          displayName: 'X.AI (Grok)',
          providerId: 'xai',
        );

      case 'qwen':
        final apiKey = await storage.get('qwen_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('qwen/', ''),
          baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
          displayName: 'Qwen (Alibaba)',
          providerId: 'qwen',
        );

      case 'moonshot':
        final apiKey = await storage.get('moonshot_api_key') ?? '';
        final cleanModel = model
            .replaceFirst('moonshot/', '')
            .replaceFirst('kimi-coding/', '');
        return OpenAIProvider(
          apiKey: apiKey,
          model: cleanModel,
          baseUrl: 'https://api.moonshot.ai/v1',
          displayName: 'Moonshot (Kimi)',
          providerId: 'moonshot',
        );

      case 'nvidia':
        final apiKey = await storage.get('nvidia_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('nvidia/', ''),
          baseUrl: 'https://integrate.api.nvidia.com/v1',
          displayName: 'NVIDIA',
          providerId: 'nvidia',
        );

      case 'zai':
        final apiKey = await storage.get('zai_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('zai/', ''),
          baseUrl: 'https://api.z.ai/api/paas/v4',
          displayName: 'Z.AI (GLM)',
          providerId: 'zai',
        );

      case 'huggingface':
        final apiKey = await storage.get('huggingface_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('huggingface/', '').replaceFirst('hf/', ''),
          baseUrl: 'https://router.huggingface.co/v1',
          displayName: 'Hugging Face',
          providerId: 'huggingface',
        );

      case 'vllm':
        final baseUrl = await storage.get('vllm_base_url') ?? '';
        final effectiveUrl = _normalizeUrl(baseUrl, 'http://localhost:8000/v1');
        return OpenAIProvider(
          apiKey: 'vllm',
          model: model,
          baseUrl: effectiveUrl,
          displayName: 'vLLM (Local)',
          providerId: 'vllm',
        );

      case 'litellm':
        final apiKey = await storage.get('litellm_api_key') ?? 'litellm';
        final baseUrl = await storage.get('litellm_base_url') ?? '';
        final effectiveUrl =
            baseUrl.isNotEmpty ? baseUrl : 'http://localhost:4000';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model,
          baseUrl: effectiveUrl,
          displayName: 'LiteLLM',
          providerId: 'litellm',
        );

      case 'ollama':
        final baseUrl = await storage.get('ollama_base_url') ?? '';
        final effectiveUrl =
            _normalizeUrl(baseUrl, 'http://localhost:11434/v1');
        return OpenAIProvider(
          apiKey: 'ollama',
          model: model,
          baseUrl: effectiveUrl,
          displayName: 'Ollama',
          providerId: 'ollama',
        );

      case 'ipex-llm':
        final baseUrl = await storage.get('ipex-llm_base_url') ?? '';
        final effectiveUrl =
            _normalizeUrl(baseUrl, 'http://localhost:11435/v1');
        return OpenAIProvider(
          apiKey: 'ipex-llm',
          model: model,
          baseUrl: effectiveUrl,
          displayName: 'IPEX-LLM (Intel)',
          providerId: 'ipex-llm',
        );

      case 'lmstudio':
        final baseUrl = await storage.get('lmstudio_base_url') ?? '';
        final effectiveUrl =
            _normalizeUrl(baseUrl, 'http://localhost:1234/v1');
        return OpenAIProvider(
          apiKey: 'lmstudio',
          model: model,
          baseUrl: effectiveUrl,
          displayName: 'LM Studio (Local)',
          providerId: 'lmstudio',
        );

      case 'minimax':
        // MiniMax uses Anthropic Messages-compatible API
        final apiKey = await storage.get('minimax_api_key') ?? '';
        return AnthropicProvider(
          apiKey: apiKey,
          model: model.replaceFirst('minimax/', ''),
          baseUrl: 'https://api.minimax.io/anthropic/v1/messages',
          providerId: 'minimax',
          displayName: 'MiniMax',
        );

      case 'xiaomi':
        // Xiaomi MiMo uses Anthropic Messages-compatible API
        final apiKey = await storage.get('xiaomi_api_key') ?? '';
        return AnthropicProvider(
          apiKey: apiKey,
          model: model.replaceFirst('xiaomi/', ''),
          baseUrl: 'https://api.xiaomimimo.com/anthropic/v1/messages',
          providerId: 'xiaomi',
          displayName: 'Xiaomi MiMo',
        );

      case 'vercel-ai-gateway':
        final apiKey = await storage.get('vercel_ai_gateway_api_key') ?? '';
        return OpenAIProvider(
          apiKey: apiKey,
          model: model.replaceFirst('vercel-ai-gateway/', ''),
          baseUrl: 'https://ai-gateway.vercel.sh/v1',
          displayName: 'Vercel AI Gateway',
          providerId: 'vercel-ai-gateway',
        );

      case 'openai':
      default:
        final apiKey = await storage.get('openai_api_key') ??
            Env.get('OPENAI_API_KEY') ??
            '';
        return OpenAIProvider(apiKey: apiKey, model: model);
    }
  }

  static Future<List<String>> listModels({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) async {
    _log.fine('Listing models for provider: $provider (baseUrl: $baseUrl, apiKey: ${apiKey.startsWith('http') ? '[URL]' : '***'})');
    List<String> models;
    
    // Auto-detect if apiKey is actually a baseUrl (common for local providers in UI)
    if (baseUrl == null || baseUrl.isEmpty) {
      if (apiKey.startsWith('http')) {
        baseUrl = apiKey;
      }
    }

    switch (provider) {
      case 'anthropic':
        models = await AnthropicProvider.listModels(apiKey);
        break;
      case 'google':
        models = await GeminiProvider.listModels(apiKey);
        break;
      case 'deepseek':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.deepseek.com');
        break;
      case 'openrouter':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://openrouter.ai/api/v1');
        break;
      case 'lmstudio':
        final effectiveUrl =
            _normalizeUrl(baseUrl ?? '', 'http://localhost:1234/v1');
        models =
            await OpenAIProvider.listModels('lmstudio', baseUrl: effectiveUrl);
        break;
      case 'ollama':
        final effectiveUrl =
            _normalizeUrl(baseUrl ?? '', 'http://localhost:11434/v1');
        models =
            await OpenAIProvider.listModels('ollama', baseUrl: effectiveUrl);
        break;
      case 'ipex-llm':
        final effectiveUrl =
            _normalizeUrl(baseUrl ?? '', 'http://localhost:11435/v1');
        models =
            await OpenAIProvider.listModels('ipex-llm', baseUrl: effectiveUrl);
        break;
      case 'mistral':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.mistral.ai/v1');
        break;
      case 'groq':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.groq.com/openai/v1');
        break;
      case 'together':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.together.xyz/v1');
        break;
      case 'perplexity':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.perplexity.ai');
        break;
      case 'xai':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.x.ai/v1');
        break;
      case 'moonshot':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.moonshot.ai/v1');
        break;
      case 'nvidia':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://integrate.api.nvidia.com/v1');
        break;
      case 'zai':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://api.z.ai/api/paas/v4');
        break;
      case 'huggingface':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://router.huggingface.co/v1');
        break;
      case 'vllm':
        final effectiveUrl = baseUrl != null && baseUrl.isNotEmpty
            ? baseUrl
            : 'http://localhost:8000/v1';
        models = await OpenAIProvider.listModels('vllm', baseUrl: effectiveUrl);
        break;
      case 'litellm':
        final effectiveUrl = baseUrl != null && baseUrl.isNotEmpty
            ? baseUrl
            : 'http://localhost:4000';
        models = await OpenAIProvider.listModels(
            apiKey.isNotEmpty ? apiKey : 'litellm',
            baseUrl: effectiveUrl);
        break;
      case 'minimax':
        // MiniMax uses Anthropic-compatible API; no OpenAI /models endpoint available
        return ['MiniMax-M2.5', 'MiniMax-M2.5-highspeed'];
      case 'qwen':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1');
        break;
      case 'xiaomi':
        // Xiaomi uses Anthropic-compatible API; no OpenAI /models endpoint available
        return ['xiaomi-chat'];
      case 'vercel-ai-gateway':
        models = await OpenAIProvider.listModels(apiKey,
            baseUrl: 'https://ai-gateway.vercel.sh/v1');
        break;
      case 'openai':
      default:
        models = await OpenAIProvider.listModels(apiKey);
        break;
    }

    // Return all models without filtering as per user request
    return models;
  }

  static Future<ModelCapabilities> getModelCapabilities({
    required String model,
    required String provider,
    required SecureStorage storage,
  }) async {
    try {
      final p = await create(
        model: model,
        provider: provider,
        storage: storage,
      );
      return p.capabilities;
    } catch (_) {
      return ModelCapabilities.textOnly();
    }
  }

  static Future<List<Map<String, dynamic>>> listModelsDetailed({
    required String provider,
    required String apiKey,
    required SecureStorage storage,
    String? baseUrl,
  }) async {
    final modelIds = await listModels(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
    );

    final results = <Map<String, dynamic>>[];
    for (final id in modelIds) {
      try {
        final p = await create(
          model: id,
          provider: provider,
          storage: storage,
        );
        results.add({
          'id': id,
          'capabilities': p.capabilities.toJson(),
        });
      } catch (_) {
        results.add({
          'id': id,
          'capabilities': ModelCapabilities.textOnly().toJson(),
        });
      }
    }
    return results;
  }

  static Future<void> testKey({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) async {
    // Auto-detect if apiKey is actually a baseUrl (common for local providers in UI)
    if (baseUrl == null || baseUrl.isEmpty) {
      if (apiKey.startsWith('http')) {
        baseUrl = apiKey;
      }
    }

    switch (provider) {
      case 'anthropic':
        await AnthropicProvider(apiKey: apiKey).testConnection();
        break;
      case 'google':
        await GeminiProvider(apiKey: apiKey, model: 'none').testConnection();
        break;
      case 'deepseek':
        await OpenAIProvider(
          apiKey: apiKey,
          baseUrl: 'https://api.deepseek.com',
        ).testConnection();
        break;
      case 'openrouter':
        // OpenRouter's /models endpoint is public and always returns 200,
        // so we must use /auth/key to actually validate the key.
        final orUrl = Uri.parse('https://openrouter.ai/api/v1/auth/key');
        final orResponse = await http.get(
          orUrl,
          headers: {'Authorization': 'Bearer $apiKey'},
        );
        if (orResponse.statusCode != 200) {
          throw ProviderError(
            'OpenRouter key invalid (${orResponse.statusCode}): ${orResponse.body}',
            provider: 'openrouter',
          );
        }
        break;
      case 'mistral':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://api.mistral.ai/v1')
            .testConnection();
        break;
      case 'groq':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://api.groq.com/openai/v1')
            .testConnection();
        break;
      case 'together':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://api.together.xyz/v1')
            .testConnection();
        break;
      case 'perplexity':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://api.perplexity.ai')
            .testConnection();
        break;
      case 'xai':
        await OpenAIProvider(apiKey: apiKey, baseUrl: 'https://api.x.ai/v1')
            .testConnection();
        break;
      case 'moonshot':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://api.moonshot.ai/v1')
            .testConnection();
        break;
      case 'nvidia':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://integrate.api.nvidia.com/v1')
            .testConnection();
        break;
      case 'zai':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://api.z.ai/api/paas/v4')
            .testConnection();
        break;
      case 'huggingface':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://router.huggingface.co/v1')
            .testConnection();
        break;
      case 'vllm':
        final effectiveUrl = baseUrl != null && baseUrl.isNotEmpty
            ? baseUrl
            : 'http://localhost:8000/v1';
        await OpenAIProvider(
          apiKey: 'vllm',
          baseUrl: effectiveUrl,
        ).testConnection();
        break;
      case 'litellm':
        final effectiveUrl = baseUrl != null && baseUrl.isNotEmpty
            ? baseUrl
            : 'http://localhost:4000';
        await OpenAIProvider(
          apiKey:
              'litellm', // Test connection for local litellm doesn't strictly need a key, or we just use 'litellm'
          baseUrl: effectiveUrl,
        ).testConnection();
        break;
      case 'ollama':
        final effectiveUrl = baseUrl != null && baseUrl.isNotEmpty
            ? baseUrl
            : 'http://localhost:11434/v1';
        await OpenAIProvider(
          apiKey: 'ollama',
          baseUrl: effectiveUrl,
        ).testConnection();
        break;
      case 'ipex-llm':
        final effectiveUrl = baseUrl != null && baseUrl.isNotEmpty
            ? baseUrl
            : 'http://localhost:11435/v1';
        await OpenAIProvider(
          apiKey: 'ipex-llm',
          baseUrl: effectiveUrl,
        ).testConnection();
        break;
      case 'lmstudio':
        final effectiveUrl =
            _normalizeUrl(baseUrl ?? '', 'http://localhost:1234/v1');
        await OpenAIProvider(
          apiKey: 'lmstudio',
          baseUrl: effectiveUrl,
        ).testConnection();
        break;
      case 'minimax':
        await AnthropicProvider(
          apiKey: apiKey,
          baseUrl: 'https://api.minimax.io/anthropic/v1/messages',
          providerId: 'minimax',
        ).testConnection();
        break;
      case 'qwen':
        await OpenAIProvider(
                apiKey: apiKey,
                baseUrl:
                    'https://dashscope-intl.aliyuncs.com/compatible-mode/v1')
            .testConnection();
        break;
      case 'xiaomi':
        await AnthropicProvider(
          apiKey: apiKey,
          baseUrl: 'https://api.xiaomimimo.com/anthropic/v1/messages',
          providerId: 'xiaomi',
        ).testConnection();
        break;
      case 'vercel-ai-gateway':
        await OpenAIProvider(
                apiKey: apiKey, baseUrl: 'https://ai-gateway.vercel.sh/v1')
            .testConnection();
        break;
      case 'openai':
      default:
        await OpenAIProvider(apiKey: apiKey).testConnection();
        break;
    }
  }
}
