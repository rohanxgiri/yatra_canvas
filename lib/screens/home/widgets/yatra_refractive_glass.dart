import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One cached program; independent, lifetime-owned uniforms for each surface.
/// Web/Skia, asset-load failure and high-contrast requests use the fallback.
class YatraRefractiveGlass extends StatefulWidget {
  const YatraRefractiveGlass({
    required this.child,
    this.radius = 24,
    this.fill = const Color(0x18FFFFFF),
    this.borderColor = const Color(0x80FFFFFF),
    this.borderWidth = .65,
    this.blur = 2,
    this.displacement = 2.4,
    this.shadow = false,
    this.highlight = true,
    super.key,
  });

  final Widget child;
  final double radius, borderWidth, blur, displacement;
  final Color fill, borderColor;
  final bool shadow, highlight;
  static Future<ui.FragmentProgram?>? _program;

  static Future<ui.FragmentProgram?> _loadProgram() => _program ??= () async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'shaders/yatra_refractive_glass.frag',
      );
    } catch (_) {
      // Optical enhancement is optional: navigation must remain usable.
      return null;
    }
  }();

  @override
  State<YatraRefractiveGlass> createState() => _YatraRefractiveGlassState();
}

class _YatraRefractiveGlassState extends State<YatraRefractiveGlass> {
  ui.FragmentShader? _shader;
  ui.ImageFilter? _lens;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && ui.ImageFilter.isShaderFilterSupported) _load();
  }

  Future<void> _load() async {
    final program = await YatraRefractiveGlass._loadProgram();
    if (!mounted || program == null) return;
    final shader = program.fragmentShader();
    try {
      final lens = ui.ImageFilter.shader(shader);
      setState(() {
        _shader = shader;
        _lens = lens;
      });
    } catch (_) {
      shader.dispose();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final radius = BorderRadius.circular(widget.radius);
      final reduced = MediaQuery.highContrastOf(context);
      final shader = _shader;
      final canRefract =
          shader != null &&
          constraints.hasBoundedWidth &&
          constraints.hasBoundedHeight;
      if (canRefract) {
        // Float indices 0/1 and sampler 0 belong to the engine. Never set them.
        shader
          ..setFloat(2, constraints.maxWidth)
          ..setFloat(3, constraints.maxHeight)
          ..setFloat(4, widget.radius)
          ..setFloat(5, widget.displacement.clamp(0, 3.3))
          ..setFloat(6, widget.blur);
      }
      final filter = !reduced && canRefract
          ? _lens!
          : ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: widget.shadow
              ? const [
                  BoxShadow(
                    color: Color(0x0D142C53),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: filter,
            child: ColoredBox(
              color: reduced ? const Color(0xB3DCE7F4) : widget.fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: widget.highlight
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x16FFFFFF),
                            Color(0x02FFFFFF),
                            Color(0x08142C53),
                          ],
                          stops: [0, .45, 1],
                        )
                      : null,
                  border: Border.all(
                    color: widget.borderColor,
                    width: widget.borderWidth,
                  ),
                ),
                child: CustomPaint(
                  foregroundPainter: widget.highlight
                      ? _GlassEdge(widget.radius)
                      : null,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Narrow inner optical rim, not a glow or a second opaque surface.
class _GlassEdge extends CustomPainter {
  const _GlassEdge(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular((radius - 1.3).clamp(0, 100)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x30FFFFFF), Color(0x00FFFFFF), Color(0x14142C53)],
          stops: [0, .45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge oldDelegate) => radius != oldDelegate.radius;
}
