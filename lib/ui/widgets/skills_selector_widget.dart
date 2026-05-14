import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_selectable_card.dart';
import 'app_styles.dart';
import '../../core/constants.dart';
import '../../providers/gateway_provider.dart';

class SkillsSelector extends ConsumerWidget {
  const SkillsSelector({
    super.key,
    this.title,
    this.selectedSkills = const [],
    this.onChanged,
    this.isEditing = true,
    this.isManagement = false,
    this.onDelete,
    this.onTap,
  });

  final String? title;
  final List<String> selectedSkills;
  final Function(List<String>)? onChanged;
  final bool isEditing;
  final bool isManagement;
  final Function(String slug)? onDelete;
  final Function(String slug)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title == null || title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: AppSectionHeader(title ?? 'settings.agents.skills_section'),
          ),
        ref.watch(skillsProvider).when(
          skipLoadingOnReload: true,
          data: (skills) {
            if (skills.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'settings.skills.no_skills'.tr(),
                  style: const TextStyle(color: AppColors.textDim),
                ),
              );
            }

            return Column(
              children: skills.map((skill) {
                final slug = skill['slug'] as String;
                final isEnabled = selectedSkills.contains(slug);

                return _SkillItem(
                  slug: slug,
                  name: (skill['name'] as String?) ?? slug,
                  description: (skill['description'] as String?) ?? '',
                  emoji: skill['emoji'] as String?,
                  isEnabled: isEnabled,
                  isEditing: isEditing,
                  isManagement: isManagement,
                  onChanged: (val) {
                    if (onChanged == null) return;
                    final next = List<String>.from(selectedSkills);
                    if (val == true) {
                      next.add(slug);
                    } else {
                      next.remove(slug);
                    }
                    onChanged!(next);
                  },
                  onDelete: onDelete != null ? () => onDelete!(slug) : null,
                  onTap: onTap != null ? () => onTap!(slug) : null,
                );
              }).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (err, _) => Text('settings.skills.error_loading_generic'.tr()),
        ),
      ],
    );
  }
}

class _SkillItem extends StatelessWidget {
  const _SkillItem({
    required this.slug,
    required this.name,
    required this.description,
    this.emoji,
    required this.isEnabled,

    required this.isEditing,
    this.isManagement = false,
    required this.onChanged,
    this.onDelete,
    this.onTap,
  });

  final String slug;
  final String name;
  final String description;
  final String? emoji;
  final bool isEnabled;

  final bool isEditing;
  final bool isManagement;
  final ValueChanged<bool?> onChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool canToggle = isEditing;

    return AppSelectableCard(
      isSelected: isEnabled,
      onTap: isManagement ? onTap : (canToggle ? () => onChanged(!isEnabled) : null),
      leading: (emoji != null && emoji!.isNotEmpty)
          ? Text(
              emoji!,
              style: const TextStyle(
                fontSize: 24,
                fontFamilyFallback: [
                  'Apple Color Emoji',
                  'Segoe UI Emoji',
                  'Noto Color Emoji',
                  'Android Emoji',
                  'EmojiSymbols',
                ],
              ),
            )
          : const Icon(
              Icons.psychology,
              color: AppConstants.iconColorPrimary,
              size: AppConstants.iconSizeLarge,
            ),
      title: Row(
        children: [
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
              fontSize: AppConstants.fontSizeBody,
            ),
          ),

        ],
      ),
      subtitle: Text(
        description,
        style: const TextStyle(
          fontSize: AppConstants.fontSizeSmall,
          color: AppColors.textDim,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isManagement
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Edit Button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.white,
                  ).copyWith(
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.hovered)) {
                        return AppColors.primary;
                      }
                      return AppColors.white;
                    }),
                  ),
                  onPressed: onTap,
                  tooltip: 'common.edit'.tr(),
                ),
                const SizedBox(width: 4),
                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.white,
                  ).copyWith(
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.hovered)) {
                        return AppColors.error;
                      }
                      return AppColors.white;
                    }),
                  ),
                  onPressed: onDelete,
                  tooltip: 'common.delete'.tr(),
                ),
              ],
            )
          : Checkbox(
              value: isEnabled,
              activeColor: AppColors.primary,
              checkColor: AppColors.black,
              onChanged: canToggle ? onChanged : null,
            ),
    );
  }
}
