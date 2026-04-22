import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants.dart';
import '../../../../providers/shell_provider.dart';
import '../../../widgets/app_styles.dart';
import 'profile_tab.dart';
import 'agents_tab.dart';
import 'api_management_tab.dart';
import 'integrations_tab.dart';
import 'channels_tab.dart';
import 'toolbox_tab.dart';
import 'gateway_tab.dart';
import 'security_tab.dart';
import 'maintenance_tab.dart';
import 'widgets/settings_sidebar.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final List<Map<String, dynamic>> _navItems = [
    {'label': 'settings.tabs.profile', 'icon': Icons.person_outline_rounded},
    {'label': 'settings.tabs.agents_profiles', 'icon': Icons.smart_toy_outlined},
    {'label': 'settings.tabs.api_management', 'icon': Icons.vpn_key_outlined},
    {'label': 'settings.integrations.tab', 'icon': Icons.extension_outlined},
    {'label': 'settings.channels.tab', 'icon': Icons.hub_outlined},
    {'label': 'settings.toolbox.tab', 'icon': Icons.construction_rounded},
    {'label': 'settings.tabs.security', 'icon': Icons.security_rounded},
    {'label': 'settings.gateway.tab', 'icon': Icons.router_rounded},
    {'label': 'settings.maintenance.tab', 'icon': Icons.settings_backup_restore_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    context.locale;
    final selectedIndex = ref.watch(shellProvider.select((s) => s.settingsTabIndex));

    return Dialog.fullscreen(
      backgroundColor: AppColors.background,
      child: Row(
        children: [
          SettingsSidebar(
            selectedIndex: selectedIndex,
            navItems: _navItems,
            onAction: (index) => ref.read(shellProvider.notifier).setSettingsTabIndex(index),
          ),
          // MAIN CONTENT
          Expanded(
            child: Container(
              color: AppColors.background,
              child: Column(
                children: [
                  _buildContentHeader(),
                  Expanded(
                    child: IndexedStack(
                      index: selectedIndex,
                      children: [
                        ProfileTab(onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(1)),
                        AgentsTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(0),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(2),
                        ),
                        ApiManagementTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(1),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(3),
                        ),
                        IntegrationsTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(2),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(4),
                        ),
                        ChannelsTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(3),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(5),
                        ),
                        ToolboxTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(4),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(6),
                        ),
                        SecurityTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(5),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(7),
                        ),
                        GatewayTab(
                          onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(6),
                          onNext: () => ref.read(shellProvider.notifier).setSettingsTabIndex(8),
                        ),
                        MaintenanceTab(onBack: () => ref.read(shellProvider.notifier).setSettingsTabIndex(7)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppCloseButton(
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
