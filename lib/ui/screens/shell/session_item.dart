import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';
import '../../../providers/gateway_provider.dart';
import 'session_model_dialog.dart';
import '../../widgets/app_dialogs.dart';

class SessionItem extends ConsumerStatefulWidget {

  const SessionItem({
    super.key,
    required this.id,
    required this.data,
    required this.onTap,
    required this.onDeleted,
    this.isPending = false,
    this.isActive = false,
  });
  final String id;
  final dynamic data;
  final bool isPending;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  @override
  ConsumerState<SessionItem> createState() => _SessionItemState();
}

class _SessionItemState extends ConsumerState<SessionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final messageCount = (widget.data['messageCount'] as int?) ?? 0;
    final model = widget.data['model'] as String?;
    final provider = widget.data['provider'] as String?;
    final agentName = widget.data['agentName'] as String?;
    final channelType = widget.data['channelType'] as String?;
    final modelShort =
        model == null
            ? null
            : (model.contains('/') ? model.split('/').last : model);

    String subtitle;
    if (widget.isPending) {
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

    final config = ref.watch(configProvider);
    String? cronTitle;
    if (widget.id.startsWith('cron_')) {
      final agentId = widget.id.replaceFirst('cron_', '');
      final agent = config.customAgents
          .where((a) => a.id == agentId)
          .firstOrNull;
      if (agent != null && agent.cronMessage.isNotEmpty) {
        cronTitle = agent.cronMessage;
      }
    }

    String displayTitle =
        widget.data['title'] as String? ??
        cronTitle ??
        agentName ??
        config.identity.name;

    if (displayTitle.isEmpty || displayTitle == config.identity.name && widget.data['title'] == null && agentName == null && cronTitle == null) {
      displayTitle = '${'chat.session_label'.tr()} ${widget.id.substring(0, 8)}';
    }

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

    final highlight = widget.isActive || _isHovered;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.sidebarItemOuterPadding,
        vertical: 1,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: AppColors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.buttonBorderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(
              AppConstants.buttonBorderRadius,
            ),
            onTap: widget.onTap,
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color:
                        highlight
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.transparent,
                    borderRadius: BorderRadius.circular(
                      AppConstants.buttonBorderRadius,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.sidebarItemInnerPadding,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isPending
                            ? Icons.hourglass_empty_rounded
                            : Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: highlight ? AppColors.white : AppColors.textDim,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: TextStyle(
                                fontSize: AppConstants.fontSizeSidebarLabel,
                                fontWeight:
                                    widget.isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                color: highlight ? AppColors.white : AppColors.textDim,
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
                                      color: AppColors.textDim.withValues(
                                        alpha: 0.7,
                                      ),
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
                                        color: highlight
                                            ? AppColors.white.withValues(alpha: 0.2)
                                            : AppColors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(
                                          AppConstants.borderRadiusSmall,
                                        ),
                                      ),
                                      child: Text(
                                        provider != null
                                            ? '$provider: $modelShort'
                                            : modelShort,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: highlight ? AppColors.white : AppColors.textDim,
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
                          if (!widget.isPending)
                            _ModelPickerButton(
                              sessionId: widget.id,
                              sessionData: widget.data,
                            ),
                          if (!widget.isPending)
                            _DeleteButton(
                              sessionId: widget.id,
                              onDeleted: widget.onDeleted,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (highlight)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: AppColors.primary,
                    ),
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

  const _DeleteButton({required this.sessionId, required this.onDeleted});
  final String sessionId;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.delete_outline_rounded, size: 16),
      style: IconButton.styleFrom(
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.all(4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: Colors.transparent,
      ).copyWith(
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppColors.error;
          }
          return AppColors.white;
        }),
      ),

      onPressed: () async {
        final confirmed = await AppAlertDialog.showConfirmation(
          context: context,
          title: 'chat.delete_session_title'.tr(),
          content: 'chat.delete_session_content'.tr(),
          confirmLabel: 'common.delete'.tr(),
          isDestructive: true,
        );

        if (confirmed == true) {
          unawaited(ref.read(sessionsProvider.notifier).deleteSession(sessionId));
          onDeleted();
        }
      },
      tooltip: 'chat.delete_session_tooltip'.tr(),
    );
  }
}

class _ModelPickerButton extends ConsumerStatefulWidget {

  const _ModelPickerButton({
    required this.sessionId,
    required this.sessionData,
  });
  final String sessionId;
  final dynamic sessionData;

  @override
  ConsumerState<_ModelPickerButton> createState() => _ModelPickerButtonState();
}

class _ModelPickerButtonState extends ConsumerState<_ModelPickerButton> {
  void _showPicker() {
    showDialog<void>(
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
      style: IconButton.styleFrom(
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.all(4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: Colors.transparent,
      ).copyWith(
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.blueAccent;
          }
          return AppColors.white;
        }),
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
