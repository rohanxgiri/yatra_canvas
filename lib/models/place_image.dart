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

  bool get hasRemoteImage {
    final candidate = thumbnailUrl ?? url;
    final uri = candidate == null ? null : Uri.tryParse(candidate);
    return status == 'resolved' &&
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  String? get bestUrl => hasRemoteImage ? (thumbnailUrl ?? url) : null;

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
