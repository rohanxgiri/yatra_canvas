const _fallbackRoot = 'assets/images/place_fallbacks';

const Map<String, String> _fallbackByCategory = {
  'cafe': '$_fallbackRoot/cafe.webp',
  'place_of_worship': '$_fallbackRoot/temple.webp',
  'museum': '$_fallbackRoot/museum.webp',
  'park_garden': '$_fallbackRoot/park_garden.webp',
  'fort_palace': '$_fallbackRoot/fort_palace.webp',
  'lake_riverfront': '$_fallbackRoot/lake_riverfront.webp',
  'hill_viewpoint': '$_fallbackRoot/hill_viewpoint.webp',
  'market_shopping': '$_fallbackRoot/market.webp',
  'beach': '$_fallbackRoot/beach.webp',
  'desert': '$_fallbackRoot/desert.webp',
  'waterfall': '$_fallbackRoot/waterfall.webp',
  'forest': '$_fallbackRoot/forest.webp',
  'restaurant': '$_fallbackRoot/restaurant.webp',
  'hotel': '$_fallbackRoot/hotel.webp',
  'wildlife': '$_fallbackRoot/wildlife.webp',
  'landmark': '$_fallbackRoot/fort_palace.webp',
  'heritage': '$_fallbackRoot/fort_palace.webp',
  'tourism': '$_fallbackRoot/viewpoint.webp',
  'art_gallery': '$_fallbackRoot/art_gallery.webp',
  'shopping': '$_fallbackRoot/shopping.webp',
  'mountain': '$_fallbackRoot/mountain.webp',
  'viewpoint': '$_fallbackRoot/viewpoint.webp',
  'other': '$_fallbackRoot/generic_place.webp',
};

String? placeFallbackAsset({
  String? normalizedCategory,
  String? rawCategory,
  String? name,
}) {
  final normalized = normalizedCategory?.trim().toLowerCase();
  if (normalized != null &&
      normalized != 'other' &&
      _fallbackByCategory.containsKey(normalized)) {
    return _fallbackByCategory[normalized]!;
  }
  final haystack = '${rawCategory ?? ''} ${name ?? ''}'.toLowerCase();
  final tokens = RegExp(r'[a-z0-9]+')
      .allMatches(haystack)
      .map((match) => match.group(0))
      .whereType<String>()
      .toSet();
  const aliases = <String, String>{
    'temple': 'place_of_worship',
    'religious': 'place_of_worship',
    'worship': 'place_of_worship',
    'museum': 'museum',
    'fort': 'fort_palace',
    'palace': 'fort_palace',
    'landmark': 'landmark',
    'heritage': 'heritage',
    'tourism': 'tourism',
    'park': 'park_garden',
    'garden': 'park_garden',
    'lake': 'lake_riverfront',
    'river': 'lake_riverfront',
    'hill': 'hill_viewpoint',
    'viewpoint': 'hill_viewpoint',
    'mountain': 'mountain',
    'market': 'market_shopping',
    'markets': 'market_shopping',
    'shopping': 'shopping',
    'cafe': 'cafe',
    'cafes': 'cafe',
    'food': 'restaurant',
    'restaurant': 'restaurant',
    'hotel': 'hotel',
    'beach': 'beach',
    'desert': 'desert',
    'waterfall': 'waterfall',
    'forest': 'forest',
    'wildlife': 'wildlife',
    'nature': 'park_garden',
    'art': 'art_gallery',
    'gallery': 'art_gallery',
    'other': 'other',
  };
  for (final entry in aliases.entries) {
    if (tokens.contains(entry.key)) return _fallbackByCategory[entry.value]!;
  }
  if (normalized == 'other') return _fallbackByCategory['other'];
  return null;
}
