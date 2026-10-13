import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';

class AdminCollectionScreen extends StatefulWidget {
  const AdminCollectionScreen({
    required this.title,
    required this.path,
    required this.repository,
    required this.onOpen,
    this.query = const {},
    this.filters = const {},
    this.advancedFilters = const {},
    this.titleFor,
    this.subtitleFor,
    this.emptyMessage = 'No records match these filters.',
    super.key,
  });
  final String title, path, emptyMessage;
  final AdminRepository repository;
  final Map<String, String> query;
  final Map<String, List<String>> filters;
  final Map<String, String> advancedFilters;
  final void Function(BuildContext, Map<String, dynamic>) onOpen;
  final String Function(Map<String, dynamic>)? titleFor, subtitleFor;
  @override
  State<AdminCollectionScreen> createState() => _AdminCollectionScreenState();
}

class _AdminCollectionScreenState extends State<AdminCollectionScreen> {
  final _search = TextEditingController();
  final _filters = <String, String>{};
  final _rows = <Map<String, dynamic>>[];
  Map<String, String> _loadedQuery = {};
  Timer? _debounce;
  bool _loading = true, _more = false, _paging = false;
  bool _failedAppend = false;
  Object? _error;
  int _inventoryProblems = 0;
  int _sequence = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final seq = ++_sequence;
    final query = {
      for (final entry in {
        ...widget.query,
        ..._filters,
        'q': _search.text.trim(),
      }.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    setState(() {
      _error = null;
      if (append) {
        _paging = true;
      } else {
        _loading = true;
        if (!mapEquals(query, _loadedQuery)) _rows.clear();
      }
    });
    try {
      final page = await widget.repository.list(
        widget.path,
        query: query,
        offset: append ? _rows.length : 0,
      );
      if (!mounted || seq != _sequence) return;
      setState(() {
        if (!append) _rows.clear();
        _rows.addAll(page.items);
        _loadedQuery = query;
        _more = page.hasMore;
        _inventoryProblems = page.inventoryProblems;
        _loading = false;
        _paging = false;
      });
    } catch (error) {
      if (mounted && seq == _sequence) {
        setState(() {
          _error = error;
          _failedAppend = append;
          _loading = false;
          _paging = false;
        });
      }
    }
  }

  Future<void> _editFilters() async {
    final applied = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CollectionFilters(
        title: widget.title,
        labels: widget.advancedFilters,
        initial: _filters,
      ),
    );
    if (applied != null && mounted) {
      _filters.addAll(applied);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        if (widget.advancedFilters.isNotEmpty)
          IconButton(
            tooltip: 'Filters',
            onPressed: _editFilters,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search ${widget.title.toLowerCase()}',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _debounce?.cancel();
                        _search.clear();
                        _load();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) {
              // Invalidate the previous request immediately, including the
              // debounce interval before the replacement request starts.
              ++_sequence;
              _debounce?.cancel();
              setState(() {});
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => _load(),
              );
            },
          ),
        ),
        if (widget.filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final filter in widget.filters.entries)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40).clamp(
                      120,
                      260,
                    ),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${filter.key}:${_filters[filter.key] ?? ''}',
                      ),
                      decoration: InputDecoration(labelText: label(filter.key)),
                      isExpanded: true,
                      menuMaxHeight: 320,
                      initialValue: _filters[filter.key] ?? '',
                      hint: Text(label(filter.key)),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            'All ${label(filter.key)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final value in filter.value)
                          DropdownMenuItem(
                            value: value,
                            child: Text(
                              label(value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        _debounce?.cancel();
                        _filters[filter.key] = value ?? '';
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
        if (_inventoryProblems > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminNotice(
              '$_inventoryProblems release metadata files are unreadable or invalid. This list contains readable releases only.',
              error: true,
            ),
          ),
        Expanded(
          child: _loading && _rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _rows.isEmpty
              ? AdminError(error: _error!, retry: () => _load())
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _rows.length) {
                        if (_error != null) {
                          return AdminError(
                            error: _error!,
                            retry: () => _load(append: _failedAppend),
                          );
                        }
                        if (_rows.isEmpty) {
                          return AdminEmpty(widget.emptyMessage);
                        }
                        if (_paging || _loading) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _more
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: OutlinedButton(
                                  onPressed: () => _load(append: true),
                                  child: const Text('Load more'),
                                ),
                              )
                            : const SizedBox(height: 24);
                      }
                      final row = _rows[index];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: YCStyle.border),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          title: Text(
                            widget.titleFor?.call(row) ??
                                '${row['name'] ?? row['trip_name'] ?? row['action'] ?? row['id']}',
                            style: YCStyle.cardTitle,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              widget.subtitleFor?.call(row) ??
                                  '${row['state'] ?? row['email'] ?? row['status'] ?? ''}',
                              style: YCStyle.secondary,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.onOpen(context, row),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class _CollectionFilters extends StatefulWidget {
  const _CollectionFilters({
    required this.title,
    required this.labels,
    required this.initial,
  });
  final String title;
  final Map<String, String> labels, initial;
  @override
  State<_CollectionFilters> createState() => _CollectionFiltersState();
}

class _CollectionFiltersState extends State<_CollectionFilters> {
  late final controllers = {
    for (final key in widget.labels.keys)
      key: TextEditingController(
        text: key == 'since'
            ? (widget.initial[key] ?? '').split('T').first
            : widget.initial[key] ?? '',
      ),
  };
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.title} filters', style: YCStyle.sectionTitle),
          const SizedBox(height: 20),
          for (final entry in widget.labels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: controllers[entry.key],
                readOnly: entry.key == 'since',
                decoration: InputDecoration(
                  labelText: entry.value,
                  suffixIcon: entry.key == 'since'
                      ? const Icon(Icons.calendar_today_outlined)
                      : null,
                ),
                onTap: entry.key == 'since'
                    ? () async {
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          initialDate:
                              DateTime.tryParse(controllers[entry.key]!.text) ??
                              DateTime.now(),
                        );
                        if (date != null && mounted) {
                          controllers[entry.key]!.text = date
                              .toIso8601String()
                              .split('T')
                              .first;
                        }
                      }
                    : null,
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.key == 'since' && entry.value.text.isNotEmpty
                    ? '${entry.value.text}T00:00:00Z'
                    : entry.value.text.trim(),
            }),
            child: const Text('Apply filters'),
          ),
          TextButton(
            onPressed: () {
              for (final controller in controllers.values) {
                controller.clear();
              }
            },
            child: const Text('Clear filters'),
          ),
        ],
      ),
    ),
  );
}
