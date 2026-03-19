import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';

class FolderItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder Header
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isCollapsed
                      ? Icons.folder_outlined
                      : Icons.folder_open_outlined,
                  size: 16,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agentName,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Delete Folder Button
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  color: AppColors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  tooltip: 'sidebar.delete_folder_tooltip'.tr(),
                  onPressed: onDelete,
                ),
                Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_right
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppColors.textDim,
                ),
              ],
            ),
          ),
        ),
        // Folder content (Sessions)
        if (!isCollapsed)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Column(children: children),
          ),
      ],
    );
  }
}
