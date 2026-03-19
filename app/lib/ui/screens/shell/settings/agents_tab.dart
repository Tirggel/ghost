import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../widgets/app_styles.dart';
import 'identity_tab.dart';
import 'custom_agents_tab.dart';
import '../../../../core/constants.dart';

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
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: AppDropdownField<int>(
            value: _currentIndex,
            items: List.generate(_subTabLabels.length, (index) => index),
            onChanged: (index) {
              if (index != null) {
                setState(() => _currentIndex = index);
              }
            },
            displayValue: (index) => _subTabLabels[index].tr(),
          ),
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
