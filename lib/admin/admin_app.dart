import 'package:flutter/material.dart';

import '../main.dart';
import '../models/auth_controller.dart';

class YatraCanvasAdminApp extends StatelessWidget {
  const YatraCanvasAdminApp({this.auth, super.key});
  final AuthController? auth;

  @override
  Widget build(BuildContext context) {
    return YatraCanvasApp(auth: auth, requireAuthentication: true);
  }
}
