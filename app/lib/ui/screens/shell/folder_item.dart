import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';

class FolderItem extends StatefulWidget {
  final String agentName;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final List<Widget> children;

  const FolderItem({
    super.key,
    required this.agentName,
    required this.isCollapsed,
    required this.onToggle,
    required this.onDelete,
    required this.children,
  });

  @override
  State<FolderItem> createState() => _FolderItemState();
}

class _FolderItemState extends State<FolderItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = _isHovered || !widget.isCollapsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder Header
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.sidebarPaddingHorizontal,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isCollapsed
                        ? Icons.folder_outlined
                        : Icons.folder_open_outlined,
                    size: 16,
                    color: highlight ? AppColors.white : AppColors.textDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.agentName,
                      style: TextStyle(
                        color: highlight ? AppColors.white : AppColors.textDim,
                        fontSize: AppConstants.fontSizeSidebarLabel,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Delete Folder Button
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.white,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(24, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      overlayColor: Colors.transparent,
                    ).copyWith(
                      foregroundColor:
                          WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return AppColors.error;
                        }
                        return AppColors.white;
                      }),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    tooltip: 'sidebar.delete_folder_tooltip'.tr(),
                    onPressed: widget.onDelete,
                  ),
                  Icon(
                    widget.isCollapsed
                        ? Icons.keyboard_arrow_right
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: highlight ? AppColors.white : AppColors.textDim,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Folder content (Sessions)
        if (!widget.isCollapsed)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Column(children: widget.children),
          ),
      ],
    );
  }
}
