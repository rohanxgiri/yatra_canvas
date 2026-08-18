import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onSelected(!selected) : null,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 44),
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
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? AppColors.tealDark
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      color: enabled
                          ? selected
                                ? AppColors.tealDark
                                : AppColors.charcoal
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 7),
                  const Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: AppColors.tealDark,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
