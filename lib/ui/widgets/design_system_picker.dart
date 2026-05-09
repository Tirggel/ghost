import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';
import '../../providers/gateway_provider.dart';
import 'app_styles.dart';

class DesignSystemPicker extends ConsumerWidget {
  const DesignSystemPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemsAsync = ref.watch(designSystemsProvider);

    return systemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Text('Error loading design systems', style: const TextStyle(color: AppColors.error)),
      data: (systems) {
        final items = [
          DropdownMenuItem(
            value: '',
            child: Text('settings.agents.design_system_none'.tr(), style: const TextStyle(color: AppColors.textDim)),
          ),
          ...systems.map((s) {
            final sys = s as Map<String, dynamic>;
            return DropdownMenuItem(
              value: sys['id'] as String,
              child: Text(sys['name'] as String, style: const TextStyle(color: AppColors.white)),
            );
          }),
        ];

        // Ensure selectedId exists in items, else default to ''
        final validValue = items.any((i) => i.value == selectedId) ? selectedId : '';

        return DropdownButtonFormField<String>(
          value: validValue,
          items: items,
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
          decoration: AppInputDecoration.standard('settings.agents.design_system_label'.tr()),
          dropdownColor: AppColors.surface,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textDim),
        );
      },
    );
  }
}
