import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/onboarding_canvas.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/yatra_brand.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const YatraBrand(compact: true),
                      const SizedBox(height: 38),
                      Text(
                        'PLAN  •  DISCOVER  •  REMEMBER',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Turn your travel ideas\ninto a journey.',
                        style: AppTextStyles.display,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Shape a thoughtful trip from the moment you arrive, '
                        'with every place connected into one clear story.',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 30),
                      const _WelcomeIllustration(),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .88),
                  border: const Border(top: BorderSide(color: Colors.white)),
                ),
                child: PrimaryButton(
                  label: 'Start Your Journey',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _open(context, const LoginScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.55,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFEAF0FF)],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18315EEB),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            const Positioned(
              left: 32,
              bottom: 28,
              child: _MapPin(icon: Icons.temple_hindu_rounded),
            ),
            const Positioned(
              right: 46,
              top: 30,
              child: _MapPin(icon: Icons.landscape_rounded, warm: true),
            ),
            Positioned(
              right: 24,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tealDark,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x29173783),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  '2 days · 8 places',
                  style: AppTextStyles.caption.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.icon, this.warm = false});

  final IconData icon;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: warm ? AppColors.terracotta : AppColors.teal,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.tealLight
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final route = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = -1; i < 6; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 70), line);
    }
    for (var i = 0; i < 6; i++) {
      final x = size.width * (i / 5);
      canvas.drawLine(Offset(x, 0), Offset(x - 50, size.height), line);
    }
    final path = Path()
      ..moveTo(size.width * .18, size.height * .72)
      ..cubicTo(
        size.width * .34,
        size.height * .5,
        size.width * .52,
        size.height * .78,
        size.width * .72,
        size.height * .32,
      );
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
