enum PlaceCategory { religious, food, tourism, cafes, heritage }

extension PlaceCategoryLabel on PlaceCategory {
  String get apiValue => name;

  String get label => switch (this) {
    PlaceCategory.religious => 'Religious',
    PlaceCategory.food => 'Food',
    PlaceCategory.tourism => 'Tourism',
    PlaceCategory.cafes => 'Cafes',
    PlaceCategory.heritage => 'Heritage',
  };

  static Set<PlaceCategory> categoriesForPurposes(Iterable<String> purposes) {
    final categories = <PlaceCategory>{};
    for (final purpose in purposes) {
      switch (purpose) {
        case 'Religious / Spiritual':
          categories.add(PlaceCategory.religious);
          break;
        case 'Culture & Heritage':
          categories.add(PlaceCategory.heritage);
          break;
        case 'Food Exploration':
          categories.add(PlaceCategory.food);
          break;
        case 'Photography':
          categories.addAll([PlaceCategory.tourism, PlaceCategory.heritage]);
          break;
        case 'Mixed Trip':
          categories.addAll(PlaceCategory.values);
          break;
        case 'Sightseeing':
        case 'Nature':
        case 'Relaxation':
        case 'Family Trip':
        case 'Shopping':
          categories.add(PlaceCategory.tourism);
          break;
      }
    }
    return categories;
  }
}

class Place {
  const Place({
    required this.id,
    required this.cityId,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.reviewCount,
    required this.isPopular,
    required this.isHeritage,
    required this.isLocalSpeciality,
    this.rating,
    this.lastFetchedAt,
  });

  final String id;
  final String cityId;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final double? rating;
  final int reviewCount;
  final bool isPopular;
  final bool isHeritage;
  final bool isLocalSpeciality;
  final DateTime? lastFetchedAt;

  factory Place.fromJson(Map<String, dynamic> json) {
    final lastFetchedAt = json['last_fetched_at'] as String?;
    return Place(
      id: json['id'] as String,
      cityId: json['city_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int,
      isPopular: json['is_popular'] as bool,
      isHeritage: json['is_heritage'] as bool,
      isLocalSpeciality: json['is_local_speciality'] as bool,
      lastFetchedAt: lastFetchedAt == null
          ? null
          : DateTime.tryParse(lastFetchedAt),
    );
  }
}
