import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/place_image.dart';
import '../utils/place_image_fallbacks.dart';
import 'yc_skeleton.dart';

class PlaceImage extends StatelessWidget {
  const PlaceImage({
    required this.name,
    this.image,
    this.normalizedCategory,
    this.rawCategory,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.showAttribution = false,
    this.testImageProvider,
    super.key,
  });

  final String name;
  final PlaceImageData? image;
  final String? normalizedCategory;
  final String? rawCategory;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool showAttribution;

  /// Allows deterministic widget tests without changing production networking.
  final ImageProvider? testImageProvider;

  @override
  Widget build(BuildContext context) {
    final remoteUrl = image?.bestUrl;
    final state = image?.state ?? PlaceImageState.unknown;
    final attribution = image?.attribution;

    Widget fallback({required Key key, required bool showUnavailableLabel}) {
      final assetPath = placeFallbackAsset(
        normalizedCategory: normalizedCategory,
        rawCategory: rawCategory,
        name: name,
      );
      if (assetPath == null) {
        return _NeutralPlaceFallback(
          key: key,
          normalizedCategory: normalizedCategory,
          rawCategory: rawCategory,
          showUnavailableLabel: showUnavailableLabel,
        );
      }
      return _LocalPlaceFallback(
        key: key,
        assetPath: assetPath,
        fit: fit,
        normalizedCategory: normalizedCategory,
        rawCategory: rawCategory,
        showUnavailableLabel: showUnavailableLabel,
      );
    }

    Widget content;
    if (testImageProvider != null) {
      content = Image(
        key: const Key('place_image_state_success'),
        image: testImageProvider!,
        fit: fit,
      );
    } else if (remoteUrl != null) {
      content = CachedNetworkImage(
        key: const Key('place_image_remote'),
        imageUrl: remoteUrl,
        fit: fit,
        memCacheWidth: 900,
        maxWidthDiskCache: 1200,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 90),
        placeholder: (_, _) => const _ImageLoadingPlaceholder(),
        imageBuilder: (context, provider) => Stack(
          fit: StackFit.expand,
          children: [
            Image(
              key: const Key('place_image_state_success'),
              image: provider,
              fit: fit,
            ),
            if (showAttribution &&
                attribution != null &&
                attribution.isNotEmpty)
              _ImageAttribution(attribution: attribution),
          ],
        ),
        errorWidget: (_, _, _) => fallback(
          key: const Key('place_image_state_error'),
          showUnavailableLabel: true,
        ),
      );
    } else {
      content = fallback(
        key: Key(
          state == PlaceImageState.notFound
              ? 'place_image_state_not_found'
              : state == PlaceImageState.error
              ? 'place_image_state_error'
              : 'place_image_state_unknown',
        ),
        showUnavailableLabel: state != PlaceImageState.unknown,
      );
    }

    return Semantics(
      image: true,
      label: '$name place photo',
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );
  }
}

class _LocalPlaceFallback extends StatelessWidget {
  const _LocalPlaceFallback({
    required this.assetPath,
    required this.fit,
    required this.normalizedCategory,
    required this.rawCategory,
    required this.showUnavailableLabel,
    super.key,
  });

  final String assetPath;
  final BoxFit fit;
  final String? normalizedCategory;
  final String? rawCategory;
  final bool showUnavailableLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    key: const Key('place_image_local_fallback'),
    fit: fit,
    errorBuilder: (_, _, _) => _NeutralPlaceFallback(
      normalizedCategory: normalizedCategory,
      rawCategory: rawCategory,
      showUnavailableLabel: showUnavailableLabel,
    ),
  );
}

class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder();

  @override
  Widget build(BuildContext context) => const YCSkeletonPulse(
    label: 'Loading place photo',
    child: ColoredBox(
      key: Key('place_image_state_loading'),
      color: Color(0xFFF0F3F8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: YCSkeletonBlock(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
  );
}

class _NeutralPlaceFallback extends StatelessWidget {
  const _NeutralPlaceFallback({
    required this.normalizedCategory,
    required this.rawCategory,
    required this.showUnavailableLabel,
    super.key,
  });

  final String? normalizedCategory;
  final String? rawCategory;
  final bool showUnavailableLabel;

  IconData get _icon {
    final category = '${normalizedCategory ?? ''} ${rawCategory ?? ''}'
        .toLowerCase();
    if (category.contains('worship') || category.contains('religious')) {
      return Icons.temple_hindu_outlined;
    }
    if (category.contains('museum') || category.contains('heritage')) {
      return Icons.museum_outlined;
    }
    if (category.contains('cafe') ||
        category.contains('restaurant') ||
        category.contains('food')) {
      return Icons.restaurant_outlined;
    }
    if (category.contains('market') || category.contains('shopping')) {
      return Icons.storefront_outlined;
    }
    if (category.contains('park') ||
        category.contains('forest') ||
        category.contains('nature')) {
      return Icons.park_outlined;
    }
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final canShowLabel =
          showUnavailableLabel &&
          constraints.maxWidth >= 120 &&
          constraints.maxHeight >= 92;
      return DecoratedBox(
        key: const Key('place_image_neutral_fallback'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2F5F1), Color(0xFFE2EBE7)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                color: const Color(0xFF52706B),
                size: canShowLabel ? 30 : 24,
              ),
              if (canShowLabel) ...[
                const SizedBox(height: 8),
                Text(
                  'Photo unavailable',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF52706B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _ImageAttribution extends StatelessWidget {
  const _ImageAttribution({required this.attribution});

  final String attribution;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 6,
    bottom: 6,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          attribution,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    ),
  );
}
