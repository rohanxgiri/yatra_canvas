import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class DestinationCard extends StatelessWidget {
  const DestinationCard({
    required this.name,
    required this.location,
    this.image,
    this.tag,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final String name;
  final String location;
  final ImageProvider? image;
  final String? tag;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$name, $location',
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: selected ? AppColors.teal : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _DestinationImage(image: image),
                    if (selected)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: AppColors.teal,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMuted,
                          ),
                        ],
                      ),
                    ),
                    if (tag != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tealLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.tealDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationImage extends StatelessWidget {
  const _DestinationImage({this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    if (image != null) {
      return Image(image: image!, fit: BoxFit.cover);
    }
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.canvasGradient),
      child: Center(
        child: Icon(
          Icons.landscape_rounded,
          size: 48,
          color: AppColors.teal,
        ),
      ),
    );
  }
}
