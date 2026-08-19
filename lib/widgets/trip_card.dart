import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class TripCard extends StatelessWidget {
  const TripCard({
    required this.title,
    required this.destination,
    required this.dateRange,
    this.image,
    this.progress,
    this.memberCount,
    this.onTap,
    super.key,
  }) : assert(progress == null || (progress >= 0 && progress <= 1));

  final String title;
  final String destination;
  final String dateRange;
  final ImageProvider? image;
  final double? progress;
  final int? memberCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2.05,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image == null
                      ? const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.tealGradient,
                          ),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Icon(
                                Icons.route_rounded,
                                color: Colors.white54,
                                size: 64,
                              ),
                            ),
                          ),
                        )
                      : Image(image: image!, fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Text(
                      destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _TripMeta(
                        icon: Icons.calendar_today_outlined,
                        text: dateRange,
                      ),
                      if (memberCount != null)
                        _TripMeta(
                          icon: Icons.group_outlined,
                          text:
                              '$memberCount ${memberCount == 1 ? 'traveler' : 'travelers'}',
                        ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppColors.tealLight,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${(progress! * 100).round()}% planned',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripMeta extends StatelessWidget {
  const _TripMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(text, style: AppTextStyles.caption),
      ],
    );
  }
}
