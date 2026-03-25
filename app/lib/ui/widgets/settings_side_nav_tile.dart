import 'package:flutter/material.dart';
import '../../../core/constants.dart';

class SettingsSideNavTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const SettingsSideNavTile({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<SettingsSideNavTile> createState() => _SettingsSideNavTileState();
}

class _SettingsSideNavTileState extends State<SettingsSideNavTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Show white indicator and tonal shift on active OR hover
    final bool highlight = widget.isActive || _isHovered;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 48,
              decoration: BoxDecoration(
                color: highlight ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  AppConstants.buttonBorderRadius,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.sidebarPaddingHorizontal,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    color:
                        widget.isActive ? AppColors.primary : AppColors.textDim,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isActive
                            ? AppColors.primary
                            : AppColors.textDim,
                        fontSize: 12,
                        fontWeight:
                            widget.isActive ? FontWeight.w900 : FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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
    );
  }
}
