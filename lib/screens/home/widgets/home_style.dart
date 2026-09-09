import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Measurements from the approved 700 x 1463 frame, node 18:16.
/// Scale by available width, never by the height of a particular device.
abstract final class HomeStyle {
  static const designWidth = 700.0;
  static const designHeight = 1463.0;
  static const ink = Color(0xFF141B34);
  static const assetRoot = 'lib/assets/home/';
  static TextStyle text(
    double size, {
    Color color = Colors.black,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: 'HomeInter',
    fontSize: size,
    height: 1.203125,
    fontWeight: weight,
    color: color,
    letterSpacing: 0,
    fontVariations: const [FontVariation('opsz', 14)],
  );

  static double extraTextHeight(BuildContext context, double height) =>
      height *
      (MediaQuery.textScalerOf(context).scale(16) / 16 - 1).clamp(0, 4);
}

class HomeIcon extends StatelessWidget {
  const HomeIcon(this.name, {required this.width, double? height, super.key})
    : height = height ?? width;
  final String name;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    '${HomeStyle.assetRoot}$name.svg',
    width: width,
    height: height,
    fit: BoxFit.fill,
    excludeFromSemantics: true,
  );
}

/// Enlarges the interactive region without altering the approved visual size.
class HomeAction extends StatefulWidget {
  const HomeAction({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.toggled,
    super.key,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final bool? toggled;
  @override
  State<HomeAction> createState() => _HomeActionState();
}

class _HomeActionState extends State<HomeAction> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    button: true,
    selected: widget.selected,
    toggled: widget.toggled,
    onTap: widget.onTap,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onFocusChange: (value) {
        if (!value) _setPressed(false);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: DecoratedBox(
            // Keyboard-only focus cue, never a pointer hover state layer.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: _focused
                  ? Border.all(color: HomeStyle.ink, width: 1.5)
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(child: ExcludeSemantics(child: widget.child)),
            ),
          ),
        ),
      ),
    ),
  );
}
