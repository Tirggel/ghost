import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/shell_provider.dart';
import '../../../../core/models/chat_session.dart';
import '../../../../providers/gateway_provider.dart';
import '../sidebar_header.dart';
import '../sidebar_footer.dart';
import '../session_item.dart';
import '../folder_item.dart';
import '../../../widgets/app_sidebar.dart';

class MainSidebar extends ConsumerWidget {
  final VoidCallback onNewChat;
  final TextEditingController searchController;
  final VoidCallback onShowSettings;
  final Function(String agentName, List<ChatSession> sessions) onConfirmDeleteFolder;

  const MainSidebar({
    super.key,
    required this.onNewChat,
    required this.searchController,
    required this.onShowSettings,
    required this.onConfirmDeleteFolder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shellState = ref.watch(shellProvider);
    final activeSessionId = shellState.activeSessionId;
    final collapsedFolders = shellState.collapsedFolders;
    final query = shellState.searchQuery.toLowerCase();
    final sessions = ref.watch(sessionsProvider);
    final storedIds = sessions.map((s) => s.id).toSet();
    final showPendingNew = activeSessionId != null && !storedIds.contains(activeSessionId);
    final defaultAgentName = ref.watch(configProvider).identity.name;

    final Map<String, List<ChatSession>> groupedSessions = {};

    if (showPendingNew) {
      bool matches = true;
      if (query.isNotEmpty) {
        matches = 'new conversation'.contains(query) || (defaultAgentName.toLowerCase().contains(query));
      }
      if (matches) {
        groupedSessions[defaultAgentName] = [
          ChatSession(
            id: activeSessionId,
            messageCount: 0,
            agentName: defaultAgentName,
          )
        ];
      }
    }

    for (final s in sessions) {
      final agentName = s.agentName ?? defaultAgentName;
      final title = (s.title ?? '').toLowerCase();
      final agentLower = agentName.toLowerCase();

      if (query.isEmpty || title.contains(query) || agentLower.contains(query)) {
        groupedSessions.putIfAbsent(agentName, () => []).add(s);
      }
    }

    return AppSidebar(
      header: SidebarHeader(
        onNewChat: onNewChat,
        searchController: searchController,
      ),
      body: ListView(
        children: groupedSessions.entries.map((entry) {
          final agentName = entry.key;
          final folderSessions = entry.value;
          final isCollapsed = collapsedFolders.contains(agentName);

          return FolderItem(
            agentName: agentName,
            isCollapsed: isCollapsed,
            onToggle: () => ref.read(shellProvider.notifier).toggleFolder(agentName),
            onDelete: () => onConfirmDeleteFolder(agentName, folderSessions),
            children: folderSessions.asMap().entries.map<Widget>((itemEntry) {
              final s = itemEntry.value;
              final id = s.id;
              final isPending = showPendingNew && id == activeSessionId;
              final isActive = activeSessionId == id;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SessionItem(
                    id: id,
                    data: s.toJson(),
                    isPending: isPending,
                    isActive: isActive,
                    onTap: () => ref.read(shellProvider.notifier).setActiveSession(id),
                    onDeleted: () {
                      if (activeSessionId == id) {
                        ref.read(shellProvider.notifier).setActiveSession(null);
                      }
                    },
                  ),
                  const SizedBox(height: 2),
                ],
              );
            }).toList(),
          );
        }).toList(),
      ),
      footer: SidebarFooter(onShowSettings: onShowSettings),
    );
  }
}
