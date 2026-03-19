import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../widgets/app_styles.dart';
import 'api_keys_tab.dart';
import 'external_services_tab.dart';

class ApiManagementTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  const ApiManagementTab({super.key, this.onBack, this.onNext});

  @override
  ConsumerState<ApiManagementTab> createState() => _ApiManagementTabState();
}

class _ApiManagementTabState extends ConsumerState<ApiManagementTab> {
  int _currentIndex = 0;

  final List<String> _subTabLabels = [
    'settings.api_keys.tab',
    'settings.external_services.tab',
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
              ApiKeysTab(
                onBack: widget.onBack,
                onNext: () => setState(() => _currentIndex = 1),
              ),
              ExternalServicesTab(
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
