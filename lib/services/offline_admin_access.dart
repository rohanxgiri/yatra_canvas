import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public showcase unlock for device data. This never grants a backend role.
abstract final class OfflineAdminAccess {
  static const email = 'admin@yatracanvas.com';
  static const storageMode = 'offline_admin';
  static const schemaVersion = 1;
  static const _digest =
      '604c9a9c776950cfe32729381927af1e9842ad41b84fb5b94c3d64f928c295ab';

  static bool accepts(String email, String password) =>
      sha256
          .convert(utf8.encode('${email.trim().toLowerCase()}\n$password'))
          .toString() ==
      _digest;

  static bool isStoredMarker(Map<String, dynamic> value) =>
      value['mode'] == storageMode && value['schema_version'] == schemaVersion;

  static Map<String, dynamic> get marker => {
    'mode': storageMode,
    'schema_version': schemaVersion,
  };
}
