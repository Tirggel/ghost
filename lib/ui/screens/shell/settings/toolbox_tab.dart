import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/app_styles.dart';
import 'skills_tab.dart';
import 'design_systems_tab.dart';
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
    'settings.design_systems.section',
    'settings.memory.tab',
    'settings.browser.tab',
    'settings.workspace.tab',
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(shellProvider.select((s) => s.settingsSubTabIndices[_mainTabIndex] ?? 0));

    return AppSettingsPage(
      subTabLabels: _subTabLabels,
      currentSubTabIndex: currentIndex,
      onSubTabChanged: (index) => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, index),
      body: IndexedStack(
        index: currentIndex,
        children: [
          SkillsTab(
            topPadding: 0,
            onBack: widget.onBack,
            onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 1),
          ),
          DesignSystemsTab(
            topPadding: 0,
            onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 0),
            onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 2),
          ),
          MemoryTab(
            topPadding: 0,
            onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 1),
            onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 3),
          ),
          BrowserTab(
            topPadding: 0,
            onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 2),
            onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 4),
          ),
          FilesystemTab(
            topPadding: 0,
            onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 3),
            onNext: widget.onNext,
          ),
        ],
      ),
    );
  }
}
