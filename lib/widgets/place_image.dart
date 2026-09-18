import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/place_image.dart';
import '../utils/place_image_fallbacks.dart';

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
    final fallback = placeFallbackAsset(
      normalizedCategory: normalizedCategory,
      rawCategory: rawCategory,
      name: name,
    );
    final remoteUrl = image?.bestUrl;
    final attribution = image?.attribution;

    Widget content;
    if (testImageProvider != null) {
      content = Image(image: testImageProvider!, fit: fit);
    } else if (remoteUrl != null) {
      content = CachedNetworkImage(
        key: const Key('place_image_remote'),
        imageUrl: remoteUrl,
        fit: fit,
        memCacheWidth: 900,
        maxWidthDiskCache: 1200,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 90),
        placeholder: (_, _) => _FallbackImage(asset: fallback, fit: fit),
        errorWidget: (_, _, _) => _FallbackImage(asset: fallback, fit: fit),
      );
    } else {
      content = _FallbackImage(asset: fallback, fit: fit);
    }

    return Semantics(
      image: true,
      label: '$name place photo',
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (showAttribution &&
                attribution != null &&
                attribution.isNotEmpty)
              Positioned(
                right: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      attribution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FallbackImage extends StatelessWidget {
  const _FallbackImage({required this.asset, required this.fit});

  final String asset;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    key: const Key('place_image_fallback'),
    fit: fit,
    cacheWidth: 900,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => const ColoredBox(
      color: Color(0xFFEAF2F0),
      child: Center(
        child: Icon(Icons.landscape_outlined, color: Color(0xFF52706B)),
      ),
    ),
  );
}
