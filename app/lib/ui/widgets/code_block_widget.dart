import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/dracula.dart';
import 'package:highlight/highlight.dart' show Mode;
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cpp.dart';
import '../../core/constants.dart';

class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;

  const CodeBlockWidget({super.key, required this.code, this.language});

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  late CodeController _codeController;

  @override
  void initState() {
    super.initState();
    final mode = _getMode(widget.language);
    _codeController = CodeController(
      text: widget.code.trimRight(),
      language: mode,
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Mode? _getMode(String? lang) {
    if (lang == null) return null;
    switch (lang.toLowerCase()) {
      case 'python':
      case 'py':
        return python;
      case 'dart':
        return dart;
      case 'js':
      case 'javascript':
        return javascript;
      case 'html':
      case 'xml':
        return xml;
      case 'css':
        return css;
      case 'json':
        return json;
      case 'yaml':
      case 'yml':
        return yaml;
      case 'bash':
      case 'sh':
        return bash;
      case 'md':
      case 'markdown':
        return markdown;
      case 'sql':
        return sql;
      case 'rust':
      case 'rs':
        return rust;
      case 'go':
        return go;
      case 'java':
        return java;
      case 'cpp':
      case 'c++':
        return cpp;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
              color: AppColors.surface, // Or a slightly different shade
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.code_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      (widget.language ?? 'CODE').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppColors.textDim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'common.copy'.tr().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code Area
          Padding(
            padding: const EdgeInsets.all(12),
            child: CodeTheme(
              data: CodeThemeData(styles: {...draculaTheme}),
              child: CodeField(
                controller: _codeController,
                readOnly: true,
                focusNode: FocusNode(), // To avoid auto-focus
                decoration: const BoxDecoration(), // No extra borders
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
