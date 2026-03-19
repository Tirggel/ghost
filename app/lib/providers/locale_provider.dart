import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

final localeFlagsProvider =
    NotifierProvider<LocaleFlagsNotifier, Map<String, String>>(() {
      return LocaleFlagsNotifier();
    });

class LocaleFlagsNotifier extends Notifier<Map<String, String>> {
  static const _prefix = 'language_flag_';

  @override
  Map<String, String> build() {
    final Map<String, String> flags = Map.from(AppConstants.defaultFlags);

    // Load persisted flags asynchronously
    _loadPersistedFlags();

    return flags;
  }

  Future<void> _loadPersistedFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, String> updatedFlags = Map.from(state);
    bool changed = false;

    for (final code in AppConstants.defaultFlags.keys) {
      final saved = prefs.getString('$_prefix$code');
      if (saved != null && saved != updatedFlags[code]) {
        updatedFlags[code] = saved;
        changed = true;
      }
    }

    if (changed) {
      state = updatedFlags;
    }
  }

  Future<void> setFlag(String languageCode, String flag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$languageCode', flag);

    state = {...state, languageCode: flag};
  }
}
