import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/settings_sub_nav_bar.dart';
import 'identity_tab.dart';
import 'custom_agents_tab.dart';

class AgentsTab extends ConsumerStatefulWidget {

  const AgentsTab({
    super.key,
    this.onBack,
    this.onNext,
  });
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends ConsumerState<AgentsTab> {
  final int _mainTabIndex = 1;

  final List<String> _subTabLabels = [
    'settings.identity.tab',
    'settings.agents.tab',
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
              IdentityTab(
                onBack: widget.onBack,
                onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 1),
              ),
              CustomAgentsTab(
                onBack: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 0),
                onNext: widget.onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
