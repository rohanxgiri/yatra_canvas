import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/place_image.dart';
import '../utils/place_image_fallbacks.dart';
import '../services/city_pack_repository.dart';

class PlaceImage extends StatelessWidget {
  const PlaceImage({
    required this.name,
    this.image,
    this.placeId,
    this.cityName,
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
  final String? placeId;
  final String? cityName;
  final String? normalizedCategory;
  final String? rawCategory;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool showAttribution;

  /// Allows deterministic widget tests without changing production networking.
  final ImageProvider? testImageProvider;

  @override
  Widget build(BuildContext context) {
    if (placeId == null ||
        image?.bundledPath != null ||
        image?.bestUrl != null) {
      return _build(context, image);
    }
    return ValueListenableBuilder(
      valueListenable: CityPackRepository.shared.cachedImages,
      builder: (context, values, _) => _build(
        context,
        values[placeId] == null
            ? image
            : PlaceImageData.fromJson(values[placeId]!),
      ),
    );
  }

  Widget _build(BuildContext context, PlaceImageData? resolved) {
    final remoteUrl = resolved?.bestUrl;
    final state = resolved?.state ?? PlaceImageState.unknown;
    final attribution = resolved?.attribution;

    Widget fallback({required Key key, required bool showUnavailableLabel}) {
      final localImage = placeFallbackImage(
        normalizedCategory: normalizedCategory,
        rawCategory: rawCategory,
        name: name,
        cityName: cityName,
      );
      final packedPlaceWithoutPhoto =
          placeId?.startsWith('yc_') == true && localImage?.attribution == null;
      if (localImage == null || packedPlaceWithoutPhoto) {
        return _NeutralPlaceFallback(
          key: key,
          normalizedCategory: normalizedCategory,
          rawCategory: rawCategory,
          showUnavailableLabel: showUnavailableLabel || packedPlaceWithoutPhoto,
          identity: packedPlaceWithoutPhoto ? name : null,
        );
      }
      return _LocalPlaceFallback(
        key: key,
        assetPath: localImage.assetPath,
        attribution: showAttribution ? localImage.attribution : null,
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
    } else if (resolved?.bundledPath case final path?) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            showAttribution ? resolved!.assetPath ?? path : path,
            key: const Key('place_image_bundled'),
            fit: fit,
            cacheWidth: 900,
            errorBuilder: (_, _, _) => fallback(
              key: const Key('place_image_state_error'),
              showUnavailableLabel: true,
            ),
          ),
          if (showAttribution && attribution != null && attribution.isNotEmpty)
            _ImageAttribution(attribution: attribution),
        ],
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
        placeholder: (_, _) => fallback(
          key: const Key('place_image_state_loading'),
          showUnavailableLabel: false,
        ),
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
      label: '$name place image',
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );
  }
}

class _LocalPlaceFallback extends StatelessWidget {
  const _LocalPlaceFallback({
    required this.assetPath,
    required this.attribution,
    required this.fit,
    required this.normalizedCategory,
    required this.rawCategory,
    required this.showUnavailableLabel,
    super.key,
  });

  final String assetPath;
  final String? attribution;
  final BoxFit fit;
  final String? normalizedCategory;
  final String? rawCategory;
  final bool showUnavailableLabel;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        assetPath,
        key: const Key('place_image_local_fallback'),
        fit: fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _NeutralPlaceFallback(
            normalizedCategory: normalizedCategory,
            rawCategory: rawCategory,
            showUnavailableLabel: false,
          );
        },
        errorBuilder: (_, _, _) => _NeutralPlaceFallback(
          normalizedCategory: normalizedCategory,
          rawCategory: rawCategory,
          showUnavailableLabel: showUnavailableLabel,
        ),
      ),
      if (attribution case final value?) _ImageAttribution(attribution: value),
    ],
  );
}

class _NeutralPlaceFallback extends StatelessWidget {
  const _NeutralPlaceFallback({
    required this.normalizedCategory,
    required this.rawCategory,
    required this.showUnavailableLabel,
    this.identity,
    super.key,
  });

  final String? normalizedCategory;
  final String? rawCategory;
  final bool showUnavailableLabel;
  final String? identity;

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
          constraints.maxHeight >= (identity == null ? 92 : 140);
      return DecoratedBox(
        key: const Key('place_image_neutral_fallback'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: identity == null
                ? const [Color(0xFFF2F5F1), Color(0xFFE2EBE7)]
                : [
                    HSLColor.fromAHSL(
                      1,
                      identity!.codeUnits
                          .fold<int>(0, (n, c) => (n * 31 + c) % 360)
                          .toDouble(),
                      .32,
                      .94,
                    ).toColor(),
                    HSLColor.fromAHSL(
                      1,
                      identity!.codeUnits
                          .fold<int>(0, (n, c) => (n * 31 + c) % 360)
                          .toDouble(),
                      .32,
                      .84,
                    ).toColor(),
                  ],
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
                  identity == null ? 'Photo unavailable' : identity!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF52706B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (identity != null)
                  const Text(
                    'Photo unavailable offline',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF52706B)),
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
