import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import 'session_model_dialog.dart';

class SessionItem extends ConsumerWidget {
  final String id;
  final dynamic data;
  final bool isPending;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  const SessionItem({
    super.key,
    required this.id,
    required this.data,
    required this.onTap,
    required this.onDeleted,
    this.isPending = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageCount = (data['messageCount'] as int?) ?? 0;
    final model = data['model'] as String?;
    final provider = data['provider'] as String?;
    final agentName = data['agentName'] as String?;
    final channelType = data['channelType'] as String?;
    final modelShort = model == null
        ? null
        : (model.contains('/') ? model.split('/').last : model);

    String subtitle;
    if (isPending) {
      subtitle = 'chat.new_conversation'.tr();
    } else if (messageCount == 0) {
      subtitle = 'chat.empty_session'.tr();
    } else {
      subtitle = 'chat.messages_count'.tr(
        namedArgs: {
          'count': messageCount.toString(),
          'suffix': messageCount == 1 ? '' : 's',
        },
      );
    }

    String displayTitle =
        data['title'] as String? ??
        agentName ??
        ref.watch(configProvider)['identity']?['name'] as String? ??
        '${'chat.session_label'.tr()} ${id.substring(0, 8)}';

    if (channelType != null && channelType != 'gateway') {
      if (channelType == 'telegram') {
        displayTitle += ' (Telegram)';
      } else if (channelType == 'googleChat') {
        displayTitle += ' (Google Chat)';
      } else {
        displayTitle +=
            ' (${channelType[0].toUpperCase()}${channelType.substring(1)})';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.sidebarItemOuterPadding,
        vertical: 1,
      ),
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.transparent,
              borderRadius: BorderRadius.circular(
                AppConstants.buttonBorderRadius,
              ),
              border: isActive
                  ? Border.all(color: AppColors.primary.withValues(alpha: 0.4))
                  : null,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.sidebarItemInnerPadding,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  isPending
                      ? Icons.hourglass_empty_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: isActive ? AppColors.primary : AppColors.textDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isActive ? AppColors.white : AppColors.textDim,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textDim.withValues(alpha: 0.7),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (modelShort != null) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.borderRadiusSmall,
                                  ),
                                ),
                                child: Text(
                                  provider != null
                                      ? '$provider: $modelShort'
                                      : modelShort,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isPending)
                      _ModelPickerButton(sessionId: id, sessionData: data),
                    if (!isPending)
                      _DeleteButton(sessionId: id, onDeleted: onDeleted),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteButton extends ConsumerWidget {
  final String sessionId;
  final VoidCallback onDeleted;

  const _DeleteButton({required this.sessionId, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.delete_outline_rounded, size: 16),
      color: AppColors.error,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: Colors.transparent,
      ),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('chat.delete_session_title'.tr()),
            content: Text('chat.delete_session_content'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'common.delete'.tr(),
                  style: const TextStyle(color: AppColors.errorDark),
                ),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          ref.read(sessionsProvider.notifier).deleteSession(sessionId);
          onDeleted();
        }
      },
      tooltip: 'chat.delete_session_tooltip'.tr(),
    );
  }
}

class _ModelPickerButton extends ConsumerStatefulWidget {
  final String sessionId;
  final dynamic sessionData;

  const _ModelPickerButton({
    required this.sessionId,
    required this.sessionData,
  });

  @override
  ConsumerState<_ModelPickerButton> createState() => _ModelPickerButtonState();
}

class _ModelPickerButtonState extends ConsumerState<_ModelPickerButton> {
  void _showPicker() {
    showDialog(
      context: context,
      builder: (context) => SessionModelDialog(
        sessionId: widget.sessionId,
        currentModel: widget.sessionData['model'] as String?,
        currentProvider: widget.sessionData['provider'] as String?,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.smart_toy_outlined, size: 16),
      color: AppColors.white,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: Colors.transparent,
      ),
      onPressed: _showPicker,
      tooltip: 'chat.change_model_tooltip'.tr(),
    );
  }
}

// NOTE: _SessionModelDialog remains in shell_screen.dart for now or can be moved too.
// For now I'll just import it or move it to a shared place if needed.
// Actually, I'll move _SessionModelDialog to shell_screen.dart as a public widget or move it here.
// To keep things simple, I'll move it here.
