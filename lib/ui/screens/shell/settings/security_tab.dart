import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../core/constants.dart';
import '../../../../engine/system1/system1_service.dart';
import '../../../widgets/app_styles.dart';

class SecurityTab extends ConsumerStatefulWidget {
  const SecurityTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends ConsumerState<SecurityTab> with SettingsSaveMixin {
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
    await handleSave(() async {
      await ref
          .read(configProvider.notifier)
          .updateSecurity(newConfig.toJson());
    });
  }

  void _onLevelChanged(String? val) {
    if (val == null) return;
    final level = SecurityLevel.values.firstWhere((e) => e.name == val);
    final modelAvail = System1Service.instance.isModelAvailable();

    SecurityConfig updated;
    switch (level) {
      case SecurityLevel.none:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: false,
          promptHardening: false,
          restrictNetwork: false,
          promptAnalyzers: false,
          system1Middleware: false,
        );
        break;
      case SecurityLevel.low:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: false,
          promptHardening: true,
          restrictNetwork: false,
          promptAnalyzers: false,
          system1Middleware: modelAvail ? true : false,
        );
        break;
      case SecurityLevel.medium:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: true,
          promptHardening: true,
          restrictNetwork: true,
          promptAnalyzers: false,
          system1Middleware: modelAvail ? true : false,
        );
        break;
      case SecurityLevel.high:
        updated = SecurityConfig(
          level: level,
          humanInTheLoop: true,
          promptHardening: true,
          restrictNetwork: true,
          promptAnalyzers: true,
          system1Middleware: modelAvail ? true : false,
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
      topPadding: widget.topPadding,
      subTabLabels: const ['settings.security.tab'],
      children: [
        const AppSectionHeader('settings.security.section', large: true),

        // Level Dropdown
        Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.settingsSectionSpacing),
          child: Row(
            children: [
              Expanded(
                child: AppUnifiedPicker<String>(
                  value: _security.level.name,
                  label: 'settings.security.level',
                  items: const ['none', 'low', 'medium', 'high'],
                  displayValue: (String val) =>
                      'settings.security.level_$val'.tr(),
                  onChanged: _onLevelChanged,
                ),
              ),
            ],
          ),
        ),

        // Sektion 1: Interaktion & KI-Wächter
        _buildSectionCard(
          labelKey: 'settings.security.section_interaction',
          children: [
            _buildSwitchTile(
              titleKey: 'settings.security.hitl',
              descKey: 'settings.security.hitl_desc',
              value: _security.humanInTheLoop,
              onChanged: (val) =>
                  _updateConfig(_security.copyWith(humanInTheLoop: val)),
            ),
            const Divider(color: AppColors.border, height: 12, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              child: Container(
                padding: const EdgeInsets.only(left: 14),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.border, width: 2),
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    final modelAvailable =
                        System1Service.instance.isModelAvailable();
                    final system1Active =
                        modelAvailable && _security.system1Middleware;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSwitchTile(
                          titleKey: 'settings.security.system1_middleware',
                          descKey: 'settings.security.system1_middleware_desc',
                          value: system1Active,
                          onChanged: modelAvailable
                              ? (val) => _updateConfig(
                                    _security.copyWith(system1Middleware: val),
                                  )
                              : null,
                          extraSubtitle: !modelAvailable
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '⚠️ ${'settings.security.system1_model_missing'.tr()}',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        if (system1Active && !_security.humanInTheLoop)
                          Container(
                            margin: const EdgeInsets.only(top: 6, bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 14,
                                    color: AppColors.textDim,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'settings.security.system1_no_hitl_hint'
                                        .tr(),
                                    style: const TextStyle(
                                      color: AppColors.textDim,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppConstants.settingsContentSpacing),

        // Sektion 2: Prompt- & Eingabeschutz
        _buildSectionCard(
          labelKey: 'settings.security.section_prompt',
          children: [
            _buildSwitchTile(
              titleKey: 'settings.security.prompt_hardening',
              descKey: 'settings.security.prompt_hardening_desc',
              value: _security.promptHardening,
              onChanged: (val) =>
                  _updateConfig(_security.copyWith(promptHardening: val)),
            ),
            const Divider(color: AppColors.border, height: 12, thickness: 0.5),
            _buildSwitchTile(
              titleKey: 'settings.security.prompt_analyzers',
              descKey: 'settings.security.prompt_analyzers_desc',
              value: _security.promptAnalyzers,
              onChanged: (val) =>
                  _updateConfig(_security.copyWith(promptAnalyzers: val)),
            ),
          ],
        ),

        const SizedBox(height: AppConstants.settingsContentSpacing),

        // Sektion 3: System-Abschottung
        _buildSectionCard(
          labelKey: 'settings.security.section_isolation',
          children: [
            _buildSwitchTile(
              titleKey: 'settings.security.restrict_network',
              descKey: 'settings.security.restrict_network_desc',
              value: _security.restrictNetwork,
              onChanged: (val) =>
                  _updateConfig(_security.copyWith(restrictNetwork: val)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String labelKey,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionLabel(labelKey),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String titleKey,
    required String descKey,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Widget? extraSubtitle,
  }) {
    return AppSwitchListTile(
      title: Text(
        titleKey.tr(),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            descKey.tr(),
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          if (extraSubtitle != null) extraSubtitle,
        ],
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
