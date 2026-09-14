import 'package:flutter/material.dart';

import '../theme/yc_motion.dart';
import '../theme/yc_style.dart';

/// Ripple-free, accessible direct-manipulation surface with physical press
/// feedback. Use for cards, chips and map controls; buttons can use
/// [YCPressScale] to retain their native button semantics.
class YCPressable extends StatefulWidget {
  const YCPressable({
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.selected = false,
    this.toggled,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.pressedScale = .98,
    super.key,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;
  final bool selected;
  final bool? toggled;
  final bool enabled;
  final BorderRadius borderRadius;
  final double pressedScale;

  @override
  State<YCPressable> createState() => _YCPressableState();
}

class _YCPressableState extends State<YCPressable> {
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    button: widget.onTap != null,
    enabled: _enabled,
    selected: widget.selected,
    toggled: widget.toggled,
    onTap: _enabled ? widget.onTap : null,
    child: FocusableActionDetector(
      enabled: _enabled,
      mouseCursor: _enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onFocusChange: (value) {
        if (!value) _setPressed(false);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (_enabled) widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        onTap: _enabled ? widget.onTap : null,
        child: widget.pressedScale == 1
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: _focused
                      ? Border.all(color: YCStyle.blue, width: 1.5)
                      : null,
                ),
                child: widget.child,
              )
            : AnimatedScale(
                scale: _pressed ? widget.pressedScale : 1,
                duration: YCMotion.duration(context, YCMotion.press),
                curve: YCMotion.standard,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: _focused
                        ? Border.all(color: YCStyle.blue, width: 1.5)
                        : null,
                  ),
                  child: widget.child,
                ),
              ),
      ),
    ),
  );
}

/// Adds press compression around an existing semantic control without taking
/// over its tap callback or focus behavior.
class YCPressScale extends StatefulWidget {
  const YCPressScale({
    required this.child,
    this.enabled = true,
    this.scale = .98,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<YCPressScale> createState() => _YCPressScaleState();
}

class _YCPressScaleState extends State<YCPressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
    onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
    onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
    child: AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: YCMotion.duration(context, YCMotion.press),
      curve: YCMotion.standard,
      child: widget.child,
    ),
  );
}
