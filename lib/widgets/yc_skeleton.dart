import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single lightweight pulse for a complete loading composition.
///
/// Keeping the animation at the composition level avoids creating an
/// animation controller for every geometric placeholder on the screen.
class YCSkeletonPulse extends StatefulWidget {
  const YCSkeletonPulse({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  State<YCSkeletonPulse> createState() => _YCSkeletonPulseState();
}

class _YCSkeletonPulseState extends State<YCSkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  late final Animation<double> _tone = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion == reducedMotion &&
        (_controller.isAnimating || reducedMotion)) {
      return;
    }
    _reducedMotion = reducedMotion;
    if (reducedMotion) {
      _controller.stop();
      _controller.value = 1;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = ExcludeSemantics(child: widget.child);
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: _reducedMotion
          ? _YCSkeletonTone(progress: 0, child: content)
          : AnimatedBuilder(
              animation: _tone,
              child: content,
              builder: (context, child) =>
                  _YCSkeletonTone(progress: _tone.value, child: child!),
            ),
    );
  }
}

class _YCSkeletonTone extends InheritedWidget {
  const _YCSkeletonTone({required this.progress, required super.child});

  final double progress;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_YCSkeletonTone>()?.progress ??
      0;

  @override
  bool updateShouldNotify(_YCSkeletonTone oldWidget) =>
      progress != oldWidget.progress;
}

class YCSkeletonBlock extends StatelessWidget {
  const YCSkeletonBlock({
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    super.key,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Color.lerp(
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2C3440)
            : AppColors.border,
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF3A4452)
            : const Color(0xFFD7DDD9),
        _YCSkeletonTone.of(context),
      ),
      borderRadius: borderRadius,
    ),
  );
}
