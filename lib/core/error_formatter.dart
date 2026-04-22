import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';

class ErrorFormatter {
  /// Translates technical provider errors into human-readable strings.
  static String format(Object? error) {
    if (error == null) return '';
    final String msg = error.toString();

    // 1. Connection Refused / Network errors
    if (msg.contains('ECONNREFUSED') || 
        msg.contains('SocketException') || 
        msg.contains('Connection refused')) {
      return 'errors.connection_failed'.tr();
    }

    // 2. Extract inner JSON if present (common for ProviderError)
    // Pattern: ... failed (CODE): { "error": ... }
    final jsonMatch = RegExp(r'\{.*\}').firstMatch(msg);
    if (jsonMatch != null) {
      try {
        final jsonStr = jsonMatch.group(0)!;
        final decoded = json.decode(jsonStr);
        if (decoded is Map && decoded.containsKey('error')) {
          final errorObj = decoded['error'];
          if (errorObj is Map && errorObj.containsKey('message')) {
            return _mapTechnicalMessage(errorObj['message'].toString());
          }
        }
      } catch (_) {
        // Fallback to pattern matching if JSON decode fails
      }
    }

    // 3. Status code mapping (401, 429, etc.)
    if (msg.contains('(401)') || msg.contains('unauthorized')) {
      return 'errors.auth_failed'.tr();
    }
    if (msg.contains('(403)') || msg.contains('forbidden')) {
      return 'errors.invalid_key'.tr();
    }
    if (msg.contains('(404)') || msg.contains('not found')) {
      return 'errors.not_found'.tr();
    }
    if (msg.contains('(429)') || msg.contains('rate limit')) {
      return 'errors.rate_limit'.tr();
    }
    if (msg.contains('(500)') || msg.contains('(502)') || msg.contains('(503)')) {
      return 'errors.server_error'.tr();
    }

    // 4. Clean up "ProviderError [xxx]:" prefix
    var cleanMsg = msg.replaceAll(RegExp(r'ProviderError\s*\[.*?\]:'), '').trim();
    
    // If it still looks like technical jargon or is very long, try to find a sub-sentence
    if (cleanMsg.contains(' failed (') && cleanMsg.contains('):')) {
       cleanMsg = cleanMsg.split('):').last.trim();
    }

    return cleanMsg.isNotEmpty ? cleanMsg : 'common.error'.tr();
  }

  static String _mapTechnicalMessage(String techMsg) {
    final lower = techMsg.toLowerCase();
    if (lower.contains('api key') && (lower.contains('invalid') || lower.contains('incorrect'))) {
      return 'errors.invalid_key'.tr();
    }
    if (lower.contains('insufficient_quota') || lower.contains('billing')) {
      return '${'errors.rate_limit'.tr()} (Billing/Quota)';
    }
    return techMsg;
  }
}
