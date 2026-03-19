import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShellState {
  final String? activeSessionId;
  final String searchQuery;
  final Set<String> collapsedFolders;

  ShellState({
    this.activeSessionId,
    this.searchQuery = '',
    this.collapsedFolders = const {},
  });

  ShellState copyWith({
    String? activeSessionId,
    String? searchQuery,
    Set<String>? collapsedFolders,
    bool clearActiveSession = false,
  }) {
    return ShellState(
      activeSessionId: clearActiveSession
          ? null
          : (activeSessionId ?? this.activeSessionId),
      searchQuery: searchQuery ?? this.searchQuery,
      collapsedFolders: collapsedFolders ?? this.collapsedFolders,
    );
  }
}

final shellProvider = NotifierProvider<ShellNotifier, ShellState>(() {
  return ShellNotifier();
});

class ShellNotifier extends Notifier<ShellState> {
  @override
  ShellState build() {
    return ShellState();
  }

  void setActiveSession(String? sessionId) {
    state = state.copyWith(
      activeSessionId: sessionId,
      clearActiveSession: sessionId == null,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleFolder(String folder) {
    final newCollapsed = Set<String>.from(state.collapsedFolders);
    if (newCollapsed.contains(folder)) {
      newCollapsed.remove(folder);
    } else {
      newCollapsed.add(folder);
    }
    state = state.copyWith(collapsedFolders: newCollapsed);
  }
}
