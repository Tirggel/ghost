import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../core/constants.dart';
import '../../../../core/models/config_models.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_snackbar.dart';

class SecurityTab extends ConsumerStatefulWidget {

  const SecurityTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends ConsumerState<SecurityTab> {
  late SecurityConfig _security;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final config = ref.read(configProvider);
      _security = config.security;
      _isInit = true;
    }
  }

  Future<void> _updateConfig(SecurityConfig newConfig) async {
    setState(() => _security = newConfig);
    try {
      await ref.read(configProvider.notifier).updateSecurity(newConfig.toJson());
      if (mounted) {
        AppSnackBar.showSuccess(context, 'common.saved'.tr());
      }
    } catch (e) {
      // Revert if failed (optimistic UI update)
      if (mounted) {
        final currentConfig = ref.read(configProvider).security;
        setState(() => _security = currentConfig);
        AppSnackBar.showError(context, 'common.error'.tr());
      }
    }
  }

  void _onLevelChanged(String? val) {
    if (val == null) return;
    final level = SecurityLevel.values.firstWhere((e) => e.name == val);
    
    SecurityConfig updated;
    switch (level) {
      case SecurityLevel.none:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: false,
          promptHardening: false,
          restrictNetwork: false,
          promptAnalyzers: false,
        );
        break;
      case SecurityLevel.low:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: false,
          promptHardening: true,
          restrictNetwork: false,
          promptAnalyzers: false,
        );
        break;
      case SecurityLevel.medium:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: true,
          promptHardening: true,
          restrictNetwork: true,
          promptAnalyzers: false,
        );
        break;
      case SecurityLevel.high:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: true,
          promptHardening: true,
          restrictNetwork: true,
          promptAnalyzers: true,
        );
        break;
    }
    _updateConfig(updated);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (prev, next) {
      if (!_isInit) return;
      if (next.security != _security) {
        setState(() => _security = next.security);
      }
    });

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      children: [
        const AppSectionHeader('settings.security.section', large: true),
        
        // Level Dropdown
        Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<String>(
                  value: _security.level.name,
                  label: 'settings.security.level',
                  items: ['none', 'low', 'medium', 'high'],
                  displayValue: (String val) => 'settings.security.level_$val'.tr(),
                  onChanged: _onLevelChanged,
                ),
              ),
            ],
          ),
        ),

        // HITL Switch
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
          activeThumbColor: AppColors.primary,
          title: Text(
            'settings.security.hitl'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'settings.security.hitl_desc'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          value: _security.humanInTheLoop,
          onChanged: (val) => _updateConfig(_security.copyWith(humanInTheLoop: val)),
        ),

        // Prompt Hardening Switch
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
          activeThumbColor: AppColors.primary,
          title: Text(
            'settings.security.prompt_hardening'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'settings.security.prompt_hardening_desc'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          value: _security.promptHardening,
          onChanged: (val) => _updateConfig(_security.copyWith(promptHardening: val)),
        ),

        // Network Isolation
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
          activeThumbColor: AppColors.primary,
          title: Text(
            'settings.security.restrict_network'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'settings.security.restrict_network_desc'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          value: _security.restrictNetwork,
          onChanged: (val) => _updateConfig(_security.copyWith(restrictNetwork: val)),
        ),

        // Prompt Analyzers
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
          activeThumbColor: AppColors.primary,
          title: Text(
            'settings.security.prompt_analyzers'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'settings.security.prompt_analyzers_desc'.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          value: _security.promptAnalyzers,
          onChanged: (val) => _updateConfig(_security.copyWith(promptAnalyzers: val)),
        ),
      ],
    );
  }
}
