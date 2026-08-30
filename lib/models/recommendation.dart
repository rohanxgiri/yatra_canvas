import 'place.dart';

class Recommendation {
  const Recommendation({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.reviewCount,
    required this.isPopular,
    required this.isHeritage,
    required this.isLocalSpeciality,
    required this.matchedCategories,
    required this.recommendationScore,
    this.rating,
  });

  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final double? rating;
  final int reviewCount;
  final bool isPopular;
  final bool isHeritage;
  final bool isLocalSpeciality;
  final List<PlaceCategory> matchedCategories;
  final double recommendationScore;

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    final rawMatchedCategories = json['matched_categories'] as List<dynamic>;
    return Recommendation(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int,
      isPopular: json['is_popular'] as bool,
      isHeritage: json['is_heritage'] as bool,
      isLocalSpeciality: json['is_local_speciality'] as bool,
      matchedCategories: rawMatchedCategories
          .map((value) => PlaceCategory.values.byName(value as String))
          .toList(growable: false),
      recommendationScore: (json['recommendation_score'] as num).toDouble(),
    );
  }
}
