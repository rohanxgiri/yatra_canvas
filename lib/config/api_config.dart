class ApiConfig {
  ApiConfig._();

  /// Android emulators reach services on the host machine through 10.0.2.2.
  /// Override this for another device with:
  /// --dart-define=API_BASE_URL=http://YOUR_HOST_IP:8001
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001',
  );
}
