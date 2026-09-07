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

enum OpeningHoursStatus {
  known,
  closed,
  unknown;

  static OpeningHoursStatus fromString(String? value) {
    return switch (value?.trim().toUpperCase()) {
      'KNOWN' => OpeningHoursStatus.known,
      'CLOSED' => OpeningHoursStatus.closed,
      _ => OpeningHoursStatus.unknown,
    };
  }

  String get apiValue => switch (this) {
    OpeningHoursStatus.known => 'KNOWN',
    OpeningHoursStatus.closed => 'CLOSED',
    OpeningHoursStatus.unknown => 'UNKNOWN',
  };
}

class OpeningHoursInterval {
  const OpeningHoursInterval({
    required this.open,
    required this.close,
  });

  final String open;
  final String close;

  factory OpeningHoursInterval.fromJson(Map<String, dynamic> json) {
    return OpeningHoursInterval(
      open: json['open'] as String? ?? '00:00',
      close: json['close'] as String? ?? '24:00',
    );
  }

  Map<String, dynamic> toJson() => {
    'open': open,
    'close': close,
  };

  /// Returns true if given (hour, minute) is within [open, close).
  bool containsTime(int hour, int minute) {
    final currentMinutes = hour * 60 + minute;
    final openParts = open.split(':');
    final closeParts = close.split(':');
    if (openParts.length != 2 || closeParts.length != 2) return false;

    final openH = int.tryParse(openParts[0]) ?? 0;
    final openM = int.tryParse(openParts[1]) ?? 0;
    final closeH = int.tryParse(closeParts[0]) ?? 24;
    final closeM = int.tryParse(closeParts[1]) ?? 0;

    final startMinutes = openH * 60 + openM;
    final endMinutes = (closeH == 24 && closeM == 0) ? 24 * 60 : closeH * 60 + closeM;

    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
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
    this.openingHoursStatus = OpeningHoursStatus.unknown,
    this.rawOpeningHours,
    this.openingHours = const {},
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
  final OpeningHoursStatus openingHoursStatus;
  final String? rawOpeningHours;
  final Map<String, List<OpeningHoursInterval>> openingHours;

  /// Returns intervals for a given date.
  List<OpeningHoursInterval> getIntervalsForDay(DateTime date) {
    final dayKeys = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final dayKey = dayKeys[(date.weekday - 1) % 7];
    return openingHours[dayKey] ?? const [];
  }

  /// Determines if the place is open at the specified [dateTime].
  /// Returns null if status is UNKNOWN (indeterminate result).
  bool? isOpenAt(DateTime dateTime) {
    if (openingHoursStatus == OpeningHoursStatus.unknown) {
      return null;
    }
    if (openingHoursStatus == OpeningHoursStatus.closed) {
      return false;
    }

    final intervals = getIntervalsForDay(dateTime);
    if (intervals.isEmpty) {
      return false;
    }

    return intervals.any(
      (interval) => interval.containsTime(dateTime.hour, dateTime.minute),
    );
  }

  factory Place.fromJson(Map<String, dynamic> json) {
    final lastFetchedAt = json['last_fetched_at'] as String?;

    final openingHoursRaw = json['opening_hours'];
    final Map<String, List<OpeningHoursInterval>> openingHoursMap = {};
    if (openingHoursRaw is Map<String, dynamic>) {
      for (final entry in openingHoursRaw.entries) {
        if (entry.value is List) {
          openingHoursMap[entry.key.toLowerCase()] = (entry.value as List)
              .map((e) => OpeningHoursInterval.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      }
    }

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
      openingHoursStatus: OpeningHoursStatus.fromString(
        json['opening_hours_status'] as String?,
      ),
      rawOpeningHours: json['raw_opening_hours'] as String?,
      openingHours: openingHoursMap,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'city_id': cityId,
    'name': name,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
    'rating': rating,
    'review_count': reviewCount,
    'is_popular': isPopular,
    'is_heritage': isHeritage,
    'is_local_speciality': isLocalSpeciality,
    'last_fetched_at': lastFetchedAt?.toIso8601String(),
    'opening_hours_status': openingHoursStatus.apiValue,
    'raw_opening_hours': rawOpeningHours,
    'opening_hours': openingHours.map(
      (k, v) => MapEntry(k, v.map((i) => i.toJson()).toList()),
    ),
  };
}

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.source,
    this.address,
    this.distanceMeters,
    this.placeId,
    this.externalPlaceId,
  });

  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final String category;
  final double? distanceMeters;
  final String? placeId;
  final String? externalPlaceId;
  final String source;

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    return PlaceSearchResult(
      name: json['name'] as String,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] as String? ?? 'sightseeing',
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      placeId: json['place_id'] as String?,
      externalPlaceId: json['external_place_id'] as String?,
      source: json['source'] as String? ?? 'database',
    );
  }
}
