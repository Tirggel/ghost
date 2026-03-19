// Ghost — Browser Tool using Puppeteer
import 'dart:convert';
import 'package:puppeteer/puppeteer.dart' as puppeteer;
import 'package:logging/logging.dart';

import 'registry.dart';

final _log = Logger('Ghost.Tools.Browser');

/// Tool for interacting with a headless browser.
class BrowserTool extends Tool {
  BrowserTool();

  @override
  String get name => 'browser';

  @override
  String get description =>
      'Interacts with a headless web browser to navigate pages, click elements, fill forms, and read text. Useful for single-page applications or pages requiring JavaScript. Note: keep interactions simple.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['goto', 'click', 'type', 'getText', 'evaluate'],
            'description': 'The action to perform in the browser.',
          },
          'url': {
            'type': 'string',
            'description': 'The URL to navigate to (required for goto).',
          },
          'selector': {
            'type': 'string',
            'description': 'The CSS selector for click, type, or getText.',
          },
          'text': {
            'type': 'string',
            'description': 'The text to type (required for type action).',
          },
          'expression': {
            'type': 'string',
            'description': 'The JS expression to evaluate (required for evaluate).',
          },
        },
        'required': ['action'],
      };

  @override
  String getLogSummary(Map<String, dynamic> input) {
    final action = input['action'] as String?;
    switch (action) {
      case 'goto':
        return 'Navigating to ${input['url']}';
      case 'click':
        return 'Clicking ${input['selector']}';
      case 'type':
        return 'Typing into ${input['selector']}';
      case 'getText':
        return 'Reading text from ${input['selector'] ?? 'page'}';
      case 'evaluate':
        return 'Evaluating JS snippet';
      default:
        return 'Browser action: $action';
    }
  }

  puppeteer.Browser? _browser;
  puppeteer.Page? _page;
  bool? _lastHeadless;

  Future<void> _ensureBrowser(bool headless) async {
    if (_browser != null && _lastHeadless != headless) {
      _log.info('Closing browser because headless mode changed from $_lastHeadless to $headless');
      await close();
    }

    if (_browser == null) {
      _log.info('Launching browser (headless: $headless)...');
      _browser = await puppeteer.puppeteer.launch(headless: headless);
      _page = await _browser!.newPage();
      _lastHeadless = headless;
    }
  }

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> input, ToolContext context) async {
    final action = input['action'] as String?;
    if (action == null) {
      return const ToolResult.error('Missing required parameter: action');
    }

    try {
      await _ensureBrowser(context.browserHeadless);
      final page = _page!;

      switch (action) {
        case 'goto':
          final url = input['url'] as String?;
          if (url == null) return const ToolResult.error('Missing url for goto');
          await page.goto(url, wait: puppeteer.Until.networkIdle);
          return ToolResult(output: 'Successfully navigated to $url');

        case 'click':
          final selector = input['selector'] as String?;
          if (selector == null) {
            return const ToolResult.error('Missing selector for click');
          }
          await page.click(selector);
          // Wait a bit for potential navigation or DOM update
          await Future<void>.delayed(const Duration(milliseconds: 1000));
          return ToolResult(output: 'Clicked on $selector');

        case 'type':
          final selector = input['selector'] as String?;
          final text = input['text'] as String?;
          if (selector == null || text == null) {
            return const ToolResult.error('Missing selector or text for type');
          }
          await page.type(selector, text);
          return ToolResult(output: 'Typed text into $selector');

        case 'getText':
          final selector = input['selector'] as String?;
          if (selector != null) {
            final text = await page.$eval<String?>(selector, 'el => el.textContent');
            return ToolResult(output: (text ?? '').toString().trim());
          } else {
            // Get text of entire body
            final text = await page.$eval<String?>('body', 'el => el.innerText');
            return ToolResult(output: (text ?? '').toString().trim());
          }

        case 'evaluate':
          final expression = input['expression'] as String?;
          if (expression == null) {
            return const ToolResult.error('Missing expression for evaluate');
          }
          final result = await page.evaluate<dynamic>(expression);
          return ToolResult(output: jsonEncode(result));

        default:
          return ToolResult.error('Unsupported action: $action');
      }
    } catch (e) {
      return ToolResult.error('Browser action failed: $e');
    }
  }

  /// Optional: Provide a way to cleanly close the browser if needed contextually.
  /// Currently, the browser stays open until the server stops or it crashes.
  Future<void> close() async {
    if (_browser != null) {
      await _browser!.close();
      _browser = null;
      _page = null;
    }
  }
}

class BrowserTools {
  BrowserTools._();

  static void registerAll(ToolRegistry registry) {
    registry.register(BrowserTool());
  }
}
