import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class PlaceCard extends StatelessWidget {
  const PlaceCard({
    required this.name,
    required this.description,
    this.image,
    this.category,
    this.meta,
    this.selected = false,
    this.onTap,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.actionBusy = false,
    super.key,
  });
  final String name;
  final String description;
  final ImageProvider? image;
  final String? category;
  final String? meta;
  final bool selected;
  final VoidCallback? onTap;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool actionBusy;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected ? AppColors.tealLight : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? AppColors.teal : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1.8,
                    child: Image(
                      image: image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stack) => const ColoredBox(
                        color: AppColors.surfaceSoft,
                        child: Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (category != null) ...[
                          Text(
                            category!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.tealDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          name,
                          style: AppTextStyles.sectionTitle.copyWith(
                            fontSize: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Icon(
                        Icons.check_circle,
                        color: AppColors.teal,
                        semanticLabel: 'Selected',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(description, style: AppTextStyles.bodyMuted),
              if (meta != null) ...[
                const SizedBox(height: 10),
                Text(meta!, style: AppTextStyles.caption),
              ],
              if (actionLabel != null || onTap != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (onTap != null)
                      TextButton(
                        onPressed: onTap,
                        child: const Text('View details'),
                      ),
                    if (actionLabel != null)
                      TextButton.icon(
                        onPressed: actionBusy ? null : onAction,
                        icon: actionBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(actionIcon ?? Icons.add_rounded, size: 20),
                        label: Text(actionLabel!),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
