import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants.dart';
import '../../providers/gateway_provider.dart';
import 'app_styles.dart';

class SkillsSelector extends ConsumerWidget {
  final List<String> selectedSkills;
  final Function(List<String>) onChanged;
  final bool isEditing;
  final String? title;
  final bool isManagement;
  final Function(String slug, bool val)? onGlobalChanged;
  final Function(String slug)? onDelete;
  final Function(String slug)? onTap;

  const SkillsSelector({
    super.key,
    this.selectedSkills = const [],
    this.onChanged = _defaultOnChanged,
    this.isEditing = true,
    this.title,
    this.isManagement = false,
    this.onGlobalChanged,
    this.onDelete,
    this.onTap,
  });

  static void _defaultOnChanged(List<String> _) {}

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
            
            // Filter non-global skills for manual selection
            // Actually, keep them all but show global status?
            // The request just said "list of skills", so I'll keep the current behavior.
            
            return Column(
              children: skills.map((skill) {
                final slug = skill['slug'] as String;
                final isEnabled = selectedSkills.contains(slug);
                final isGlobal = skill['isGlobal'] as bool? ?? false;
                
                return _SkillItem(
                  slug: slug,
                  name: skill['name'] ?? slug,
                  description: skill['description'] ?? '',
                  emoji: skill['emoji'] as String?,
                  isEnabled: isGlobal || isEnabled,
                  isGlobal: isGlobal,
                  isEditing: isEditing,
                  isManagement: isManagement,
                  onChanged: (val) {
                    final next = List<String>.from(selectedSkills);
                    if (val == true) {
                      next.add(slug);
                    } else {
                      next.remove(slug);
                    }
                    onChanged(next);
                  },
                  onGlobalChanged: onGlobalChanged != null
                      ? (val) => onGlobalChanged!(slug, val)
                      : null,
                  onDelete: onDelete != null ? () => onDelete!(slug) : null,
                  onTap: onTap != null ? () => onTap!(slug) : null,
                );
              }).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: LinearProgressIndicator(),
          ),
          error: (_, __) => Text('settings.skills.error_loading_generic'.tr()),
        ),
      ],
    );
  }
}

class _SkillItem extends StatelessWidget {
  final String slug;
  final String name;
  final String description;
  final String? emoji;
  final bool isEnabled;
  final bool isGlobal;
  final bool isEditing;
  final bool isManagement;
  final ValueChanged<bool?> onChanged;
  final ValueChanged<bool>? onGlobalChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const _SkillItem({
    required this.slug,
    required this.name,
    required this.description,
    this.emoji,
    required this.isEnabled,
    required this.isGlobal,
    required this.isEditing,
    this.isManagement = false,
    required this.onChanged,
    this.onGlobalChanged,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool canToggle = isEditing && !isGlobal;

    return GestureDetector(
      onTap: isManagement ? onTap : (canToggle ? () => onChanged(!isEnabled) : null),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(AppConstants.cardPadding),
        decoration: BoxDecoration(
          color: isEnabled ? AppColors.background : AppColors.surface,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: isEnabled
                ? AppColors.primary
                : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Leading Icon / Emoji
            SizedBox(
              width: 40,
              child: (emoji != null && emoji!.isNotEmpty)
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
            ),
            const SizedBox(width: 14),
            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMain,
                          fontSize: AppConstants.fontSizeBody,
                        ),
                      ),
                      if (isGlobal) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.public,
                            size: 12, color: AppColors.primary),
                      ],
                    ],
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: AppConstants.fontSizeSmall,
                      color: AppColors.textDim,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Checkbox OR Management Actions
            if (isManagement) ...[
              // Global Switch
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'settings.skills.global'.tr().toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: isGlobal,
                      onChanged: onGlobalChanged,
                      activeThumbColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              // Delete Button
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppColors.error,
                ),
                onPressed: onDelete,
                tooltip: 'common.delete'.tr(),
              ),
            ] else
              Checkbox(
                value: isEnabled,
                activeColor: AppColors.primary,
                checkColor: AppColors.black,
                onChanged: canToggle ? onChanged : null,
              ),
          ],
        ),
      ),
    );
  }
}
