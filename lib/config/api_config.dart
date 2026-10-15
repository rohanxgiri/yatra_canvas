import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;

class ApiConfig {
  ApiConfig._();

  static const productionBaseUrl = 'https://yatra-canvas.onrender.com';

  /// Explicit build overrides win. Releases default to Render; debug/profile
  /// retain emulator/desktop defaults. Prepared cities still use local storage.
  static String get baseUrl => resolve(
    defined: const String.fromEnvironment('API_BASE_URL'),
    release: kReleaseMode,
    web: kIsWeb,
    platform: defaultTargetPlatform,
  );

  static String resolve({
    required String defined,
    required bool release,
    required bool web,
    required TargetPlatform platform,
  }) {
    final override = defined.trim().replaceFirst(RegExp(r'/+$'), '');
    if (override.isNotEmpty) {
      final uri = Uri.tryParse(override);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.path.isNotEmpty) {
        throw ArgumentError(
          'API_BASE_URL must be an HTTP(S) origin without credentials, a path, query, or fragment.',
        );
      }
      return override;
    }
    if (release) return productionBaseUrl;

    // 2. Android emulator reaches the host via the special alias 10.0.2.2.
    //    kIsWeb must be checked first because defaultTargetPlatform returns
    //    android on web when compiled for the Android device web view.
    if (!web && platform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }

    // 3. Everything else (web, iOS simulator, macOS/Windows/Linux desktop).
    return 'http://localhost:8000';
  }
}
