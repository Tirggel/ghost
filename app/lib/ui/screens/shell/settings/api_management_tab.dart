import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/settings_sub_nav_bar.dart';
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
