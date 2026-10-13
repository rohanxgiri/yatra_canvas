import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../admin_theme.dart';

String readable(Object? value) {
  if (value == null || value == '') return 'Not recorded';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is Map || value is List) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  return '$value';
}

String label(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
    )
    .join(' ');

/// Fetch with bearer headers first, including on web where Image.network headers
/// are not a reliable authentication transport. No token is put in a media URL.
class AdminImage extends StatefulWidget {
  const AdminImage({
    required this.repository,
    required this.cityKey,
    required this.path,
    this.height = 180,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey, path;
  final double height;
  @override
  State<AdminImage> createState() => _AdminImageState();
}

class _AdminImageState extends State<AdminImage> {
  late final Future<Uint8List> _image = widget.repository.mediaBytes(
    widget.cityKey,
    widget.path,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, result) {
      if (result.hasError) {
        return const AdminEmpty(
          'Image unavailable. Check the reference or mark it for research.',
        );
      }
      if (!result.hasData) {
        return SizedBox(
          height: widget.height,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return Image.memory(
        result.data!,
        height: widget.height,
        fit: BoxFit.contain,
        semanticLabel: 'Canonical place image',
        errorBuilder: (_, error, trace) => const AdminEmpty(
          'Image file could not be decoded. Mark it for research.',
        ),
      );
    },
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = value.toUpperCase();
    final positive = {
      'KEEP',
      'READY',
      'ACTIVE',
      'ACCEPTED',
      'COMPLETED',
      'RESOLVED',
      'PASS',
    }.contains(status);
    final critical = {
      'EXCLUDE',
      'BLOCKED',
      'REJECTED',
      'INVALID',
      'FAILED',
      'FAIL',
    }.contains(status);
    final warning = {
      'OPEN',
      'REVIEWING',
      'PENDING',
      'QUEUED',
      'STALE',
      'HIDDEN',
      'RESTRICTED',
      'NOT_CERTIFIED',
    }.contains(status);
    final color = critical
        ? scheme.error
        : positive
        ? AdminTheme.success
        : warning
        ? AdminTheme.warning
        : YCStyle.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            critical
                ? Icons.error_outline
                : positive
                ? Icons.check_circle_outline
                : warning
                ? Icons.schedule
                : Icons.info_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label(value),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminCard extends StatelessWidget {
  const AdminCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: YCStyle.border),
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    required this.title,
    required this.value,
    required this.scope,
    required this.icon,
    this.onTap,
    super.key,
  });
  final String title, scope;
  final Object? value;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: YCStyle.border),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: YCStyle.surfaceBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: YCStyle.blue, size: 20),
                ),
                const Spacer(),
                if (onTap != null) const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value == null ? 'Unavailable' : '$value',
              style: YCStyle.sectionTitle.copyWith(
                fontSize: value == null ? 18 : 30,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Text(title, style: YCStyle.cardTitle.copyWith(fontSize: 15)),
            const SizedBox(height: 6),
            Text(scope, style: YCStyle.caption),
          ],
        ),
      ),
    ),
  );
}

class AdminNotice extends StatelessWidget {
  const AdminNotice(this.message, {this.retry, this.error = false, super.key});
  final String message;
  final VoidCallback? retry;
  final bool error;
  @override
  Widget build(BuildContext context) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              color: error ? Theme.of(context).colorScheme.error : YCStyle.blue,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: YCStyle.secondary)),
          ],
        ),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class RecordSection extends StatelessWidget {
  const RecordSection(this.title, this.values, {super.key});
  final String title;
  final Map<String, dynamic> values;
  @override
  Widget build(BuildContext context) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: YCStyle.cardTitle),
        const SizedBox(height: 14),
        for (final entry in values.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label(entry.key), style: YCStyle.caption),
                const SizedBox(height: 4),
                SelectableText(readable(entry.value), style: YCStyle.secondary),
              ],
            ),
          ),
      ],
    ),
  );
}

class AdminError extends StatelessWidget {
  const AdminError({required this.error, required this.retry, super.key});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(height: 16),
          Text(
            error is AdminFailure
                ? (error as AdminFailure).message
                : 'Unable to load this view.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class AdminEmpty extends StatelessWidget {
  const AdminEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.task_alt_outlined, color: YCStyle.muted),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: YCStyle.secondary),
      ],
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class AdminAsyncScreen extends StatefulWidget {
  const AdminAsyncScreen({
    required this.title,
    required this.load,
    required this.builder,
    super.key,
  });
  final String title;
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback)
  builder;
  @override
  State<AdminAsyncScreen> createState() => _AdminAsyncScreenState();
}

class _AdminAsyncScreenState extends State<AdminAsyncScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _reload() => setState(() => _future = widget.load());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminError(error: snapshot.error!, retry: _reload);
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context, snapshot.data!, _reload);
      },
    ),
  );
}
