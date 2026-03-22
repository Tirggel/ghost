import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/settings_side_nav_tile.dart';
import 'profile_tab.dart';
import 'agents_tab.dart';
import 'api_management_tab.dart';
import 'integrations_tab.dart';
import 'channels_tab.dart';
import 'toolbox_tab.dart';
import 'widgets/settings_sidebar.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _navItems = [
    {'label': 'settings.tabs.profile', 'icon': Icons.person_outline_rounded},
    {'label': 'settings.tabs.agents_profiles', 'icon': Icons.smart_toy_outlined},
    {'label': 'settings.tabs.api_management', 'icon': Icons.vpn_key_outlined},
    {'label': 'settings.integrations.tab', 'icon': Icons.extension_outlined},
    {'label': 'settings.channels.tab', 'icon': Icons.hub_outlined},
    {'label': 'settings.toolbox.tab', 'icon': Icons.construction_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    context.locale;

    return Dialog.fullscreen(
      backgroundColor: AppColors.background,
      child: Row(
        children: [
          SettingsSidebar(
            selectedIndex: _selectedIndex,
            navItems: _navItems,
            onAction: (index) => setState(() => _selectedIndex = index),
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
                      index: _selectedIndex,
                      children: [
                        ProfileTab(onNext: () => setState(() => _selectedIndex = 1)),
                        AgentsTab(
                          onBack: () => setState(() => _selectedIndex = 0),
                          onNext: () => setState(() => _selectedIndex = 2),
                        ),
                        ApiManagementTab(
                          onBack: () => setState(() => _selectedIndex = 1),
                          onNext: () => setState(() => _selectedIndex = 3),
                        ),
                        IntegrationsTab(
                          onBack: () => setState(() => _selectedIndex = 2),
                          onNext: () => setState(() => _selectedIndex = 4),
                        ),
                        ChannelsTab(
                          onBack: () => setState(() => _selectedIndex = 3),
                          onNext: () => setState(() => _selectedIndex = 5),
                        ),
                        ToolboxTab(onBack: () => setState(() => _selectedIndex = 4)),
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
