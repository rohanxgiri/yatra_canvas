import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class ApiConfig {
  ApiConfig._();

  /// Resolves the backend base URL for the current platform.
  ///
  /// Priority:
  ///   1. `--dart-define=API_BASE_URL=...` (explicit override, any target)
  ///   2. `http://10.0.2.2:8000`  — Android emulator (host machine alias)
  ///   3. `http://localhost:8000` — Flutter web, iOS simulator, desktop
  ///
  /// Physical devices on your LAN need an explicit override:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
  static String get baseUrl {
    // 1. Explicit compile-time override wins.
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) return defined;

    // 2. Android emulator reaches the host via the special alias 10.0.2.2.
    //    kIsWeb must be checked first because defaultTargetPlatform returns
    //    android on web when compiled for the Android device web view.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }

    // 3. Everything else (web, iOS simulator, macOS/Windows/Linux desktop).
    return 'http://localhost:8000';
  }
}
