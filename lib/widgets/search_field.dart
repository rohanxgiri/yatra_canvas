import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SearchField extends StatefulWidget {
  const SearchField({
    this.controller,
    this.hintText = 'Search destinations or places',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.readOnly = false,
    this.focusNode,
    super.key,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;
  final bool readOnly;
  final FocusNode? focusNode;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_refresh);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        prefixIconColor: AppColors.textSecondary,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: _clear,
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}
