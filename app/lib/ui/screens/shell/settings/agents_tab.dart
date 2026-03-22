import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/settings_sub_nav_bar.dart';
import 'identity_tab.dart';
import 'custom_agents_tab.dart';

class AgentsTab extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const AgentsTab({
    super.key,
    this.onBack,
    this.onNext,
  });

  @override
  State<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<AgentsTab> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  final List<String> _subTabLabels = [
    'settings.identity.tab',
    'settings.agents.tab',
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
              IdentityTab(
                onBack: widget.onBack,
                onNext: () => setState(() => _currentIndex = 1),
              ),
              CustomAgentsTab(
                onBack: () => setState(() => _currentIndex = 0),
                onNext: widget.onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
