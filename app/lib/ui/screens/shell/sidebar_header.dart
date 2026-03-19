import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants.dart';

class SidebarHeader extends StatelessWidget {
  final VoidCallback onNewChat;
  final TextEditingController searchController;

  const SidebarHeader({
    super.key,
    required this.onNewChat,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onNewChat,
            icon: const Icon(Icons.add, size: 18),
            label: Text('common.new_chat'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.black,
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppConstants.buttonBorderRadius,
                ),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            style: const TextStyle(color: AppColors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'sidebar.search_placeholder'.tr(),
              hintStyle: TextStyle(
                color: AppColors.textDim.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.textDim,
              ),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: AppColors.textDim,
                      ),
                      onPressed: () => searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.border.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  AppConstants.buttonBorderRadius,
                ),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  AppConstants.buttonBorderRadius,
                ),
                borderSide: const BorderSide(color: AppColors.border, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  AppConstants.buttonBorderRadius,
                ),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
