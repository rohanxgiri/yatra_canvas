import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/yc_motion.dart';
import '../theme/yc_style.dart';

/// A contextual, honest wait state for the trip-create request. It deliberately
/// avoids percentages: the backend does not expose granular progress.
class TripGenerationExperience extends StatefulWidget {
  const TripGenerationExperience({
    required this.destination,
    this.editing = false,
    super.key,
  });

  final String destination;
  final bool editing;

  @override
  State<TripGenerationExperience> createState() =>
      _TripGenerationExperienceState();
}

class _TripGenerationExperienceState extends State<TripGenerationExperience> {
  Timer? _timer;
  int _phase = 0;

  List<String> get _phases => widget.editing
      ? const [
          'Saving your latest trip details',
          'Keeping your days and pace together',
          'Reopening your travel canvas',
        ]
      : const [
          'Creating your trip',
          'Keeping your dates and pace together',
          'Preparing your travel canvas',
        ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1450), (_) {
      if (!mounted || _phase >= _phases.length - 1) {
        _timer?.cancel();
        return;
      }
      setState(() => _phase += 1);
      if (_phase >= _phases.length - 1) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? get _imageAsset {
    final city = widget.destination.toLowerCase();
    const known = [
      'jaipur',
      'varanasi',
      'udaipur',
      'manali',
      'goa',
      'rishikesh',
    ];
    for (final name in known) {
      if (city.contains(name)) return 'lib/assets/home/$name.png';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: const Color(0xF9F6F9FF),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(YCStyle.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Semantics(
                liveRegion: true,
                label: '${_phases[_phase]} for ${widget.destination}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DestinationWindow(
                      destination: widget.destination,
                      imageAsset: _imageAsset,
                      phase: _phase,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      widget.editing
                          ? 'Updating your Yatra'
                          : 'Building your Yatra',
                      textAlign: TextAlign.center,
                      style: YCStyle.title,
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: YCMotion.duration(context, YCMotion.component),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _phases[_phase],
                        key: ValueKey(_phase),
                        textAlign: TextAlign.center,
                        style: YCStyle.body.copyWith(color: YCStyle.muted),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 12),
                    Text(
                      'Your trip will open as soon as it’s ready.',
                      textAlign: TextAlign.center,
                      style: YCStyle.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationWindow extends StatelessWidget {
  const _DestinationWindow({
    required this.destination,
    required this.imageAsset,
    required this.phase,
    required this.reduceMotion,
  });

  final String destination;
  final String? imageAsset;
  final int phase;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => Container(
    height: 210,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1714294E),
          blurRadius: 28,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (imageAsset case final asset?)
          AnimatedScale(
            scale: phase == 0 || reduceMotion ? 1 : 1.035,
            duration: reduceMotion ? Duration.zero : const Duration(seconds: 3),
            curve: Curves.easeOut,
            child: Image.asset(asset, fit: BoxFit.cover),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(gradient: YCStyle.canvas),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00141B34), Color(0xB8141B34)],
              stops: [.35, 1],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YCStyle.sectionTitle.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: 28,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(phase),
            duration: reduceMotion ? Duration.zero : YCMotion.journey,
            curve: YCMotion.standard,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) => CustomPaint(
              size: const Size(double.infinity, 72),
              painter: _JourneyThreadPainter(progress: value),
            ),
          ),
        ),
      ],
    ),
  );
}

class _JourneyThreadPainter extends CustomPainter {
  const _JourneyThreadPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8, size.height - 10)
      ..cubicTo(
        size.width * .28,
        size.height + 2,
        size.width * .58,
        4,
        size.width - 8,
        14,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: .72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final metric = path.computeMetrics().first;
    final tangent = metric.getTangentForOffset(metric.length * progress);
    if (tangent == null) return;
    canvas.drawCircle(
      tangent.position,
      5,
      Paint()..color = const Color(0xFFFCB61F),
    );
    canvas.drawCircle(
      tangent.position,
      9,
      Paint()..color = const Color(0x55FCB61F),
    );
  }

  @override
  bool shouldRepaint(_JourneyThreadPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
