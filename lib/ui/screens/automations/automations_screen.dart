import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/automations_provider.dart';
import 'automation_detail_view.dart';
import 'automations_overview.dart';

/// Top-level Automations workspace screen routing between Overview and Detail.
class AutomationsScreen extends ConsumerWidget {
  const AutomationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedAutomationIdProvider);
    if (selectedId == null) {
      return const AutomationsOverview();
    }
    return AutomationDetailView(
      key: ValueKey(selectedId),
      automationId: selectedId,
    );
  }
}
