import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/gateway_provider.dart';
import '../../core/constants.dart';

class ModelInfoBadge extends ConsumerWidget {
  const ModelInfoBadge({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch both sources; session-specific overrides global config
    final sessions = ref.watch(sessionsProvider);
    final config = ref.watch(configProvider);
    final skillsAsync = ref.watch(skillsProvider);

    final currentSession = sessions.where((s) => s.id == sessionId).firstOrNull;

    final rawModel =
        currentSession?.model ??
        config.agent.model ??
        'Unknown';
    final rawProvider =
        currentSession?.provider ??
        config.agent.provider;

    // Derive display strings
    String providerLabel = rawProvider?.toUpperCase() ?? 'AI';
    String modelLabel = rawModel;
    if (rawModel.contains('/')) {
      final parts = rawModel.split('/');
      if (rawProvider == null) providerLabel = parts[0].toUpperCase();
      modelLabel = parts.last;
    }

    // Get active skills display names
    String skillsLabel = '';
    final activeSkillSlugs = config.agent.skills;

    if (activeSkillSlugs.isNotEmpty) {
      final allSkills = skillsAsync.value ?? [];
      final skillNames = <String>[];
      for (final slug in activeSkillSlugs) {
        final skill = allSkills.where((s) => s['slug'] == slug).firstOrNull;
        if (skill != null) {
          skillNames.add(skill['name'] as String? ?? slug);
        } else {
          skillNames.add(slug);
        }
      }
      skillsLabel = skillNames.join(', ');
    }

    final iconPath = AppConstants.getProviderIcon(rawProvider ?? '');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                providerLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                modelLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.white,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (skillsLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    skillsLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textDim.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        if (iconPath.isNotEmpty) ...[
          const SizedBox(width: 12),
          Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(
                AppConstants.borderRadiusSmall,
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Image.asset(
              iconPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.psychology,
                size: 20,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
