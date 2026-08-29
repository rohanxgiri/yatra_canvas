import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'screens/admin_panel_screen.dart';

class YatraCanvasAdminApp extends StatelessWidget {
  const YatraCanvasAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YatraCanvas Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AdminPanelScreen(),
    );
  }
}
