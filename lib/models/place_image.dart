enum PlaceImageState { unknown, loading, success, notFound, error }

class PlaceImageData {
  const PlaceImageData({
    this.url,
    this.thumbnailUrl,
    this.provider,
    this.sourceUrl,
    this.attribution,
    this.author,
    this.license,
    this.licenseUrl,
    this.status = 'not_found',
  });

  final String? url;
  final String? thumbnailUrl;
  final String? provider;
  final String? sourceUrl;
  final String? attribution;
  final String? author;
  final String? license;
  final String? licenseUrl;
  final String status;

  PlaceImageState get state {
    switch (status) {
      case 'resolved':
        return _validRemoteUrl == null
            ? PlaceImageState.error
            : PlaceImageState.success;
      case 'not_found':
        return PlaceImageState.notFound;
      case 'failed':
        return PlaceImageState.error;
      default:
        return PlaceImageState.unknown;
    }
  }

  String? get _validRemoteUrl {
    final candidate = thumbnailUrl ?? url;
    final uri = candidate == null ? null : Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    return candidate;
  }

  bool get hasRemoteImage => state == PlaceImageState.success;

  String? get bestUrl => hasRemoteImage ? _validRemoteUrl : null;

  factory PlaceImageData.fromJson(Map<String, dynamic> json) => PlaceImageData(
    url: json['url'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    provider: json['provider'] as String?,
    sourceUrl: json['source_url'] as String?,
    attribution: json['attribution'] as String?,
    author: json['author'] as String?,
    license: json['license'] as String?,
    licenseUrl: json['license_url'] as String?,
    status: json['status'] as String? ?? 'not_found',
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'thumbnail_url': thumbnailUrl,
    'provider': provider,
    'source_url': sourceUrl,
    'attribution': attribution,
    'author': author,
    'license': license,
    'license_url': licenseUrl,
    'status': status,
  };
}
