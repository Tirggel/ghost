import 'package:flutter/material.dart';

class AppConstants {
  static final GlobalKey<ScaffoldMessengerState> snackbarKey =
      GlobalKey<ScaffoldMessengerState>();

  static const String appName = 'Ghost';
  static const String appVersion = 'v1.0.0-alpha';

  // UI Constants
  static const double settingsIconSize = 20.0;
  static const double indicatorSizeSmall = 6.0;
  static const double iconSizeTiny = 16.0;
  static const double iconSizeSmall = 18.0;
  static const double iconSizeMedium = 20.0;
  static const double iconSizeLarge = 24.0;
  static const double iconSizeExtraLarge = 28.0;

  static const IconData folderIcon = Icons.folder_open;
  static const Color folderIconColor = AppColors.white;

  static const Color iconColorPrimary = AppColors.primary;
  static const Color iconColorError = AppColors.error;
  static const Color iconColorSuccess = AppColors.success;
  static const Color iconColorWarning = AppColors.warning;
  static const Color iconColorWhite = AppColors.white;
  static const Color iconColorDim = AppColors.textDim;

  static const double sidebarPaddingHorizontal = 14.0;
  static const double sidebarPaddingVertical = 14.0;
  static const double sidebarItemOuterPadding = 14.0;
  static const double sidebarItemInnerPadding = 14.0;
  static const double defaultPadding = 16.0;
  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusDefault = 6.0;
  static const double borderRadiusLarge = 8.0;
  static const double timestampFontSize = 10.0;
  static const double buttonBorderRadius = 0.0;

  // Spacing
  static const double settingsPagePadding = 20.0;
  static const double settingsTopPadding = 24.0;
  static const double settingsHeaderBottomPadding = 16.0;

  static const double cardPadding = 14.0; // inner padding of selectable cards
  static const double iconBoxSize = 36.0; // step-header icon container size
  static const double iconBoxIconSize = 18.0; // icon inside iconBox

  // Typography scale
  static const double fontSizeCaption = 13.0; // session subtitles, model badges
  static const double fontSizeSmall = 13.0; // secondary info, hints
  static const double fontSizeBody = 13.0; // labels, inputs, dropdowns
  static const double fontSizeSubhead = 14.0; // dialog section headers
  static const double fontSizeTitle = 16.0; // settings section headers
  static const double fontSizeLead = 20.0; // wizard step titles
  static const double fontSizeHeading = 22.0; // sidebar app name
  static const double fontSizeLabelTiny = 11.0; // All-caps section labels / small titles
  static const double fontSizeSidebarLabel = 12.0; // Labels in sidebar items (sessions, folders, settings)
  static const double fontSizeDisplay = 28.0; // wizard header title

  static const double avatarRadius = 28.0;
  static const double avatarIconSize = 28.0;

  static const String defaultGatewayUrl = String.fromEnvironment(
    'GATEWAY_URL',
    defaultValue: 'ws://127.0.0.1:3000',
  );

  // Providers & Services
  static const List<Map<String, String>> aiProviders = [
    {'id': 'anthropic', 'label': 'Anthropic (Claude)', 'icon': 'anthropic.png'},
    {'id': 'deepseek', 'label': 'DeepSeek', 'icon': 'deepseek-color.png'},
    {'id': 'google', 'label': 'Google (Gemini)', 'icon': 'gemini-color.png'},
    {'id': 'grok', 'label': 'Grok (xAI)', 'icon': 'grok.png'},
    {
      'id': 'huggingface',
      'label': 'Hugging Face',
      'icon': 'huggingface-color.png',
    },
    {'id': 'litellm', 'label': 'LiteLLM (Local)', 'icon': 'litellm.png'},
    {'id': 'minimax', 'label': 'MiniMax', 'icon': 'minimax-color.png'},
    {'id': 'mistral', 'label': 'Mistral AI', 'icon': 'mistral-color.png'},
    {'id': 'moonshot', 'label': 'Moonshot (Kimi)', 'icon': 'moonshot.png'},
    {'id': 'nvidia', 'label': 'NVIDIA', 'icon': 'nvidia-color.png'},
    {'id': 'ollama', 'label': 'Ollama (Local)', 'icon': 'ollama.png'},
    {'id': 'openai', 'label': 'OpenAI (GPT)', 'icon': 'openai.png'},
    {'id': 'openrouter', 'label': 'OpenRouter', 'icon': 'openrouter.png'},
    {'id': 'perplexity', 'label': 'Perplexity', 'icon': 'perplexity-color.png'},
    {'id': 'qwen', 'label': 'Qwen (Alibaba)', 'icon': 'qwen-color.png'},
    {'id': 'together', 'label': 'Together AI', 'icon': 'together-color.png'},
    {
      'id': 'vercel-ai-gateway',
      'label': 'Vercel AI Gateway',
      'icon': 'vercel.png',
    },
    {'id': 'vllm', 'label': 'vLLM (Local)', 'icon': 'vllm-color.png'},
    {'id': 'xiaomi', 'label': 'Xiaomi MiMo', 'icon': 'xiaomimimo.png'},
    {'id': 'zai', 'label': 'Z.AI (GLM)', 'icon': 'zai.png'},
  ];

  static String getProviderIcon(String id) {
    final provider = aiProviders.firstWhere(
      (p) => p['id'] == id,
      orElse: () => {},
    );
    final icon = provider['icon'];
    if (icon == null) return ''; 
    return 'assets/icons/llm/$icon';
  }

  static const List<Map<String, String>> chatChannels = [
    {'id': 'whatsapp', 'label': 'settings.channels.whatsapp', 'icon': 'whatsapp.png'},
    {'id': 'telegram', 'label': 'settings.channels.telegram', 'icon': 'telegram.png'},
    {'id': 'discord', 'label': 'settings.channels.discord', 'icon': 'discord.png'},
    {'id': 'slack', 'label': 'settings.channels.slack', 'icon': 'slack.png'},
    {'id': 'signal', 'label': 'settings.channels.signal', 'icon': 'signal.png'},
    {'id': 'imessage', 'label': 'settings.channels.imessage', 'icon': 'imessage.png'},
    {'id': 'msTeams', 'label': 'settings.channels.msteams', 'icon': 'msteams.png'},
    {'id': 'nextcloudTalk', 'label': 'settings.channels.nextcloud', 'icon': 'nextcloudtalk.png'},
    {'id': 'matrix', 'label': 'settings.channels.matrix', 'icon': 'matrix.png'},
    {'id': 'nostr', 'label': 'settings.channels.nostr', 'icon': 'nostr.png'},
    {'id': 'tlon', 'label': 'settings.channels.tlon', 'icon': 'tlon.png'},
    {'id': 'zalo', 'label': 'settings.channels.zalo', 'icon': 'zalo.png'},
    {'id': 'webchat', 'label': 'settings.channels.webchat', 'icon': 'webchat.png'},
    {'id': 'googleChat', 'label': 'settings.channels.googlechat', 'icon': 'google.png'},
  ];

  static String getChannelIcon(String id) {
    final channel = chatChannels.firstWhere(
      (c) => c['id'] == id,
      orElse: () => {},
    );
    final icon = channel['icon'];
    if (icon == null) return ''; 
    return 'assets/icons/channels/$icon';
  }

  static const Map<String, String> defaultFlags = {'en': '🇬🇧', 'de': '🇩🇪'};
}

class AppColors {
  // Theme Colors: The Monolith (Strictly Monochromatic)
  static const Color primary = Color(0xFFFFFFFF); // Pure White
  static const Color pureBlack = Color(0xFF000000);
  static const Color background = Color(0xFF09090B); // Deep Zinc 950
  static const Color surface = Color(0xFF18181B); // Zinc 900
  static const Color surfaceLight = Color(0xFF27272A); // Zinc 800 (Hover)
  static const Color surfaceDark = Color(0xFF09090B); // Zinc 950 (Background)
  static const Color border = Color(0xFF27272A); // Zinc 800
  static const Color textMain = Color(0xFFFAFAFA); // White-ish
  static const Color textDim = Color(0xFFA1A1AA); // Zinc 400

  // Semantic Colors
  static const MaterialAccentColor error = Colors.redAccent;
  static const MaterialColor errorDark = Colors.red;
  static const MaterialColor success = Colors.green;
  static const MaterialColor warning = Colors.orange;

  // Standard utility colors
  static const Color black = Colors.black;
  static const Color black26 = Colors.black26;
  static const Color black12 = Colors.black12;
  static const Color white = Colors.white;
  static const Color transparent = Colors.transparent;

  // Custom Opacity colors
  static final Color overlayBackground = Colors.black.withValues(alpha: 0.5);
}
