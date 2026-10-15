import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/config/api_config.dart';

void main() {
  String resolve({
    String defined = '',
    bool release = false,
    bool web = false,
    TargetPlatform platform = TargetPlatform.android,
  }) => ApiConfig.resolve(
    defined: defined,
    release: release,
    web: web,
    platform: platform,
  );

  test('release defaults to hosted HTTPS on every platform', () {
    for (final platform in TargetPlatform.values) {
      expect(
        resolve(release: true, platform: platform),
        ApiConfig.productionBaseUrl,
      );
    }
    expect(resolve(release: true, web: true), ApiConfig.productionBaseUrl);
  });
  test('debug emulator and desktop/web retain development defaults', () {
    expect(resolve(), 'http://10.0.2.2:8000');
    expect(resolve(web: true), 'http://localhost:8000');
    expect(resolve(platform: TargetPlatform.windows), 'http://localhost:8000');
  });
  test(
    'explicit public origin overrides either mode and normalizes slashes',
    () {
      expect(
        resolve(defined: ' https://staging.example/// ', release: true),
        'https://staging.example',
      );
      expect(
        resolve(defined: 'http://192.168.1.4:8000', release: true),
        'http://192.168.1.4:8000',
      );
    },
  );
  test('invalid origins and credential URLs fail without echoing input', () {
    for (final value in [
      'abc',
      'https://',
      'ftp://api.test',
      'https://user:secret@api.test',
      'https://api.test?key=secret',
      'https://api.test/path',
      'https://api.test#fragment',
    ]) {
      expect(() => resolve(defined: value), throwsArgumentError);
    }
  });
  test('actual compile time override is used by the running test binary', () {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      expect(ApiConfig.baseUrl, defined.replaceFirst(RegExp(r'/+$'), ''));
    }
  });
}
