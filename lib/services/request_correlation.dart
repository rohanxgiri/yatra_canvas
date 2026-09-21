import 'dart:math';

class RequestCorrelation {
  RequestCorrelation._();

  static final RegExp _safe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
  static final Random _random = Random.secure();

  static String resolve(String? candidate) {
    final normalized = candidate?.trim();
    if (normalized != null && _safe.hasMatch(normalized)) return normalized;
    return _newUuidV4();
  }

  static String _newUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
