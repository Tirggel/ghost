import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShellState {

  ShellState({
    this.activeSessionId,
    this.searchQuery = '',
    this.collapsedFolders = const {},
    this.settingsTabIndex = 0,
    this.settingsSubTabIndices = const {},
    this.pendingSettingsOpen = false,
  });
  final String? activeSessionId;
  final String searchQuery;
  final Set<String> collapsedFolders;
  final int settingsTabIndex;
  final Map<int, int> settingsSubTabIndices;
  final bool pendingSettingsOpen;

  ShellState copyWith({
    String? activeSessionId,
    String? searchQuery,
    Set<String>? collapsedFolders,
    int? settingsTabIndex,
    Map<int, int>? settingsSubTabIndices,
    bool clearActiveSession = false,
    bool? pendingSettingsOpen,
  }) {
    return ShellState(
      activeSessionId: clearActiveSession
          ? null
          : (activeSessionId ?? this.activeSessionId),
      searchQuery: searchQuery ?? this.searchQuery,
      collapsedFolders: collapsedFolders ?? this.collapsedFolders,
      settingsTabIndex: settingsTabIndex ?? this.settingsTabIndex,
      settingsSubTabIndices: settingsSubTabIndices ?? this.settingsSubTabIndices,
      pendingSettingsOpen: pendingSettingsOpen ?? this.pendingSettingsOpen,
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

  void setSettingsTabIndex(int index) {
    state = state.copyWith(settingsTabIndex: index);
  }

  void setPendingSettingsOpen(bool value) {
    state = state.copyWith(pendingSettingsOpen: value);
  }

  void setSettingsSubTabIndex(int mainTabIndex, int subTabIndex) {
    final updatedSubTabs = Map<int, int>.from(state.settingsSubTabIndices);
    updatedSubTabs[mainTabIndex] = subTabIndex;
    state = state.copyWith(settingsSubTabIndices: updatedSubTabs);
  }
}
