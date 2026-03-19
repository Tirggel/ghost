import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants.dart';
import '../../../widgets/app_styles.dart';
import 'profile_tab.dart';
import 'agents_tab.dart';
import 'api_management_tab.dart';
import 'integrations_tab.dart';
import 'channels_tab.dart';
import 'toolbox_tab.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _tabLabels = [
    'settings.tabs.profile',
    'settings.tabs.agents_profiles',
    'settings.tabs.api_management',
    'settings.integrations.tab',
    'settings.channels.tab',
    'settings.toolbox.tab',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch context.locale to ensure rebuild on language change
    context.locale;

    return Dialog.fullscreen(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ProfileTab(onNext: () => _tabController.animateTo(1)),
                AgentsTab(
                  onBack: () => _tabController.animateTo(0),
                  onNext: () => _tabController.animateTo(2),
                ),
                ApiManagementTab(
                  onBack: () => _tabController.animateTo(1),
                  onNext: () => _tabController.animateTo(3),
                ),
                IntegrationsTab(
                  onBack: () => _tabController.animateTo(2),
                  onNext: () => _tabController.animateTo(4),
                ),
                ChannelsTab(
                  onBack: () => _tabController.animateTo(3),
                  onNext: () => _tabController.animateTo(5),
                ),
                ToolboxTab(onBack: () => _tabController.animateTo(4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'settings.title'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              AppCloseButton(
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppDropdownField<int>(
            value: _tabController.index,
            items: List.generate(_tabLabels.length, (index) => index),
            onChanged: (index) {
              if (index != null) {
                _tabController.animateTo(index);
              }
            },
            displayValue: (index) => _tabLabels[index].tr(),
          ),
        ],
      ),
    );
  }
}
