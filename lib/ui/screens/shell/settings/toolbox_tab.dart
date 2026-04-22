import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/settings_sub_nav_bar.dart';
import 'skills_tab.dart';
import 'memory_tab.dart';
import 'browser_tab.dart';
import 'filesystem_tab.dart';

class ToolboxTab extends ConsumerStatefulWidget {

  const ToolboxTab({
    super.key,
    this.onBack,
    this.onNext,
  });
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<ToolboxTab> createState() => _ToolboxTabState();
}

class _ToolboxTabState extends ConsumerState<ToolboxTab> {
  final int _mainTabIndex = 5;

  final List<String> _subTabLabels = [
    'settings.skills.tab',
    'settings.memory.tab',
    'settings.browser.tab',
    'settings.workspace.tab',
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(shellProvider.select((s) => s.settingsSubTabIndices[_mainTabIndex] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSubNavBar(
          items: _subTabLabels,
          currentIndex: currentIndex,
          onTap: (index) => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, index),
        ),
        Expanded(
          child: IndexedStack(
            index: currentIndex,
            children: [
              SkillsTab(
                onBack: widget.onBack,
                onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 1),
              ),
              MemoryTab(
                onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 0),
                onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 2),
              ),
              BrowserTab(
                onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 1),
                onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 3),
              ),
              FilesystemTab(
                onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 2),
                onNext: widget.onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
