const _fallbackRoot = 'assets/images/place_fallbacks';
const _jaipurPackRoot = 'assets/city_packs/jaipur/images';

class PlaceFallbackImage {
  const PlaceFallbackImage({required this.assetPath, this.attribution});

  final String assetPath;
  final String? attribution;
}

const Map<String, PlaceFallbackImage> _jaipurPlaceImages = {
  'albert hall museum': PlaceFallbackImage(
    assetPath:
        '$_jaipurPackRoot/yc_in_rj_jaipur_albert_hall_museum/primary.webp',
    attribution: 'Photo: Anjaliup79 · CC BY-SA 4.0',
  ),
  'amber fort': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_amber_fort/primary.webp',
    attribution: 'Photo: xiquinhosilva · CC BY 2.0',
  ),
  'birla mandir': PlaceFallbackImage(
    assetPath:
        '$_jaipurPackRoot/yc_in_rj_jaipur_birla_mandir_aka_the_marble_temple/primary.webp',
    attribution: 'Photo: Jean-Marc Astesana from Voisins le Bretonneux, France · CC BY-SA 2.0',
  ),
  'birla mandir aka the marble temple': PlaceFallbackImage(
    assetPath:
        '$_jaipurPackRoot/yc_in_rj_jaipur_birla_mandir_aka_the_marble_temple/primary.webp',
    attribution: 'Photo: Jean-Marc Astesana from Voisins le Bretonneux, France · CC BY-SA 2.0',
  ),
  'city palace': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_city_palace/primary.webp',
    attribution: 'Photo: Rakesh Krishna Kumar · CC BY-SA 2.0',
  ),
  'hawa mahal': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_hawa_mahal/primary.webp',
    attribution: 'Photo: Chainwit. · CC BY-SA 4.0',
  ),
  'jaigarh fort': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_jaigarh_fort/primary.webp',
    attribution: 'Photo: Ashwin Kumar from Bangalore, India · CC BY-SA 2.0',
  ),
  'jal mahal': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_jal_mahal/primary.webp',
    attribution: 'Photo: Jakub Hałun · CC BY-SA 4.0',
  ),
  'jantar mantar': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_jantar_mantar/primary.webp',
    attribution: 'Photo: Knowledge Seeker · Public domain',
  ),
  'nahargarh fort': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_nahargarh_fort/primary.webp',
    attribution: 'Photo: Yoge cool · CC BY-SA 4.0',
  ),
  'patrika gate': PlaceFallbackImage(
    assetPath: '$_jaipurPackRoot/yc_in_rj_jaipur_patrika_gate/primary.webp',
    attribution: 'Photo: Darshanavenugopal · CC BY-SA 4.0',
  ),
};

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
  String? cityName,
}) {
  return placeFallbackImage(
    normalizedCategory: normalizedCategory,
    rawCategory: rawCategory,
    name: name,
    cityName: cityName,
  )?.assetPath;
}

PlaceFallbackImage? placeFallbackImage({
  String? normalizedCategory,
  String? rawCategory,
  String? name,
  String? cityName,
}) {
  final city = _normalizedWords(cityName);
  final placeName = _normalizedWords(name);
  if (city == 'jaipur') {
    final cityPackImage = _jaipurPlaceImages[placeName];
    if (cityPackImage != null) return cityPackImage;
  }

  final normalized = normalizedCategory?.trim().toLowerCase();
  final nameTokens = _tokens(name);
  const nameAliases = <String, String>{
    'temple': 'place_of_worship',
    'mandir': 'place_of_worship',
    'masjid': 'place_of_worship',
    'mosque': 'place_of_worship',
    'church': 'place_of_worship',
    'museum': 'museum',
    'fort': 'fort_palace',
    'palace': 'fort_palace',
    'mahal': 'fort_palace',
    'haveli': 'fort_palace',
    'park': 'park_garden',
    'garden': 'park_garden',
    'lake': 'lake_riverfront',
    'river': 'lake_riverfront',
    'hill': 'hill_viewpoint',
    'viewpoint': 'hill_viewpoint',
    'mountain': 'mountain',
    'market': 'market_shopping',
    'bazaar': 'market_shopping',
    'cafe': 'cafe',
    'restaurant': 'restaurant',
    'hotel': 'hotel',
    'beach': 'beach',
    'desert': 'desert',
    'waterfall': 'waterfall',
    'forest': 'forest',
    'gallery': 'art_gallery',
  };
  const broadCategories = {'other', 'tourism', 'heritage', 'landmark'};
  if (normalized == null || broadCategories.contains(normalized)) {
    for (final entry in nameAliases.entries) {
      if (nameTokens.contains(entry.key)) {
        return PlaceFallbackImage(assetPath: _fallbackByCategory[entry.value]!);
      }
    }
  }

  if (normalized != null &&
      normalized != 'other' &&
      _fallbackByCategory.containsKey(normalized)) {
    return PlaceFallbackImage(assetPath: _fallbackByCategory[normalized]!);
  }
  final haystack = '${rawCategory ?? ''} ${name ?? ''}'.toLowerCase();
  final tokens = _tokens(haystack);
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
    if (tokens.contains(entry.key)) {
      return PlaceFallbackImage(assetPath: _fallbackByCategory[entry.value]!);
    }
  }
  if (normalized == 'other') {
    return PlaceFallbackImage(assetPath: _fallbackByCategory['other']!);
  }
  return null;
}

String _normalizedWords(String? value) => _tokens(value).join(' ');

Set<String> _tokens(String? value) =>
    RegExp(r'[a-z0-9]+')
        .allMatches(value?.toLowerCase() ?? '')
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet();
