import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/yc_motion.dart';
import '../models/place_image.dart';
import 'place_image.dart';
import 'yc_pressable.dart';

class PlaceCard extends StatelessWidget {
  const PlaceCard({
    required this.name,
    required this.description,
    this.image,
    this.imageData,
    this.normalizedCategory,
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
  final PlaceImageData? imageData;
  final String? normalizedCategory;
  final String? category;
  final String? meta;
  final bool selected;
  final VoidCallback? onTap;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool actionBusy;
  @override
  Widget build(BuildContext context) => YCPressable(
    onTap: onTap,
    enabled: onTap != null,
    semanticLabel: name,
    selected: selected,
    borderRadius: BorderRadius.circular(24),
    child: AnimatedContainer(
      duration: YCMotion.duration(context, YCMotion.component),
      curve: YCMotion.standard,
      decoration: BoxDecoration(
        color: selected ? AppColors.tealLight : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? AppColors.teal : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10142C53),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null || imageData != null || category != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image != null
                          ? Image(image: image!, fit: BoxFit.cover)
                          : PlaceImage(
                              name: name,
                              image: imageData,
                              normalizedCategory: normalizedCategory,
                              rawCategory: category,
                            ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x52000000)],
                            stops: [.55, 1],
                          ),
                        ),
                      ),
                      if (category != null)
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .9),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              category!,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.tealDark,
                              ),
                            ),
                          ),
                        ),
                      if (selected)
                        const Positioned(
                          right: 12,
                          top: 12,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.teal,
                            child: Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
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
                      Text(
                        name,
                        style: AppTextStyles.sectionTitle.copyWith(
                          fontSize: 21,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected && image == null && imageData == null)
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
  );
}
