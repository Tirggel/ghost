import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/settings_sub_nav_bar.dart';
import 'skills_tab.dart';
import 'memory_tab.dart';
import 'browser_tab.dart';
import 'filesystem_tab.dart';
import '../../../../core/constants.dart';

class ToolboxTab extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const ToolboxTab({
    super.key,
    this.onBack,
    this.onNext,
  });

  @override
  State<ToolboxTab> createState() => _ToolboxTabState();
}

class _ToolboxTabState extends State<ToolboxTab> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  final List<String> _subTabLabels = [
    'settings.skills.tab',
    'settings.memory.tab',
    'settings.browser.tab',
    'settings.workspace.tab',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSubNavBar(
          items: _subTabLabels,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
        ),
        Expanded(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              SkillsTab(
                onBack: widget.onBack,
                onNext: () => setState(() => _currentIndex = 1),
              ),
              MemoryTab(
                onBack: () => setState(() => _currentIndex = 0),
                onNext: () => setState(() => _currentIndex = 2),
              ),
              BrowserTab(
                onBack: () => setState(() => _currentIndex = 1),
                onNext: () => setState(() => _currentIndex = 3),
              ),
              FilesystemTab(
                onBack: () => setState(() => _currentIndex = 2),
                onNext: widget.onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
