import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import '../screens/admin_shell.dart';

/// Compatibility entry point with the same role guard as the main application.
class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      AdminShell(auth: AuthController.instance);
}
