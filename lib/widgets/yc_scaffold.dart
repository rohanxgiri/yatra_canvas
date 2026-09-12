import 'package:flutter/material.dart';

import '../theme/yc_style.dart';

/// Shared page surface for screens outside the approved Home / Explore shell.
class YCScaffold extends StatelessWidget {
  const YCScaffold({
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    super.key,
  });
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  @override
  Widget build(BuildContext context) => Theme(
    data: YCStyle.theme(context),
    child: Scaffold(
      appBar: appBar,
      body: YCCanvas(child: body),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    ),
  );
}

class YCStateCard extends StatelessWidget {
  const YCStateCard({
    required this.title,
    required this.message,
    this.icon = Icons.explore_outlined,
    this.loading = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final String title;
  final String message;
  final IconData icon;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: loading,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(YCStyle.cardRadius),
        border: Border.all(color: YCStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: YCStyle.blue, size: 24),
          const SizedBox(height: 14),
          Text(title, style: YCStyle.sectionTitle),
          const SizedBox(height: 8),
          Text(message, style: YCStyle.secondary),
          if (loading) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel ?? 'Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}
