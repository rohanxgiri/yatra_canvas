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
    this.assetPath,
    this.thumbnailAssetPath,
    this.mediaClass,
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
  final String? assetPath;
  final String? thumbnailAssetPath;
  final String? mediaClass;

  String? get bundledPath {
    final path = thumbnailAssetPath ?? assetPath;
    return path != null &&
            path.startsWith('assets/citypacks/') &&
            !path.contains('..') &&
            !path.contains('\\')
        ? path
        : null;
  }

  PlaceImageState get state {
    switch (status) {
      case 'resolved':
        if (bundledPath != null) return PlaceImageState.success;
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

  bool get hasRemoteImage =>
      _validRemoteUrl != null && state == PlaceImageState.success;

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
    assetPath: json['asset_path'] as String?,
    thumbnailAssetPath: json['thumbnail_asset_path'] as String?,
    mediaClass: json['media_class'] as String?,
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
    'asset_path': assetPath,
    'thumbnail_asset_path': thumbnailAssetPath,
    'media_class': mediaClass,
  };
}
