import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/yc_motion.dart';
import 'yc_pressable.dart';

class SelectionChip extends StatelessWidget {
  const SelectionChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return YCPressable(
      semanticLabel: label,
      selected: selected,
      enabled: enabled,
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? () => onSelected(!selected) : null,
      child: AnimatedContainer(
        duration: YCMotion.duration(context, YCMotion.component),
        curve: YCMotion.standard,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealLight : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AnimatedScale(
                scale: selected ? 1.06 : 1,
                duration: YCMotion.duration(context, YCMotion.component),
                curve: YCMotion.standard,
                child: Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? AppColors.tealDark
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: enabled
                      ? selected
                            ? AppColors.tealDark
                            : AppColors.charcoal
                      : AppColors.textTertiary,
                ),
              ),
            ),
            AnimatedSize(
              duration: YCMotion.duration(context, YCMotion.component),
              curve: YCMotion.standard,
              child: selected
                  ? const Padding(
                      padding: EdgeInsets.only(left: 7),
                      child: Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: AppColors.tealDark,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
