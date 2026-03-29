import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/shell_provider.dart';
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
  final int _mainTabIndex = 2;

  final List<String> _subTabLabels = [
    'settings.api_keys.tab',
    'settings.external_services.tab',
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
              ApiKeysTab(
                onBack: widget.onBack,
                onNext: () => ref.read(shellProvider.notifier).setSettingsSubTabIndex(_mainTabIndex, 1),
              ),
              ExternalServicesTab(
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
