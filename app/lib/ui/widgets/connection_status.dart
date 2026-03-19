import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/gateway_provider.dart';
import '../../core/gateway.dart';
import '../../core/constants.dart';

class ConnectionStatusWidget extends ConsumerWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    return status.when(
      data: (s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppConstants.indicatorSizeSmall,
            height: AppConstants.indicatorSizeSmall,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s == ConnectionStatus.authenticated
                  ? AppConstants.iconColorSuccess
                  : AppConstants.iconColorWarning,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            s == ConnectionStatus.authenticated
                ? 'chat.connected'.tr()
                : s.name.toUpperCase(),
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
      loading: () => Text(
        'chat.connecting'.tr(),
        style: const TextStyle(fontSize: 11, color: AppColors.textDim),
      ),
      error: (_, _) => Text(
        'chat.offline'.tr(),
        style: const TextStyle(fontSize: 11, color: AppConstants.iconColorError),
      ),
    );
  }
}
