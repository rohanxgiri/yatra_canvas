import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class YatraBrand extends StatelessWidget {
  const YatraBrand({this.compact = false, this.light = false, super.key});

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : AppColors.charcoal;
    final accent = AppColors.marigold;
    return Semantics(
      label: 'YatraCanvas',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 34 : 54,
            height: compact ? 34 : 54,
            decoration: BoxDecoration(
              gradient: light ? null : AppColors.tealGradient,
              color: light ? Colors.white12 : null,
              borderRadius: BorderRadius.circular(compact ? 10 : 17),
              border: Border.all(
                color: light ? Colors.white24 : Colors.white,
                width: light ? 1 : 1.5,
              ),
              boxShadow: light
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x24315EEB),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.route_rounded,
                  color: Colors.white,
                  size: compact ? 23 : 34,
                ),
                Positioned(
                  right: compact ? 4 : 7,
                  top: compact ? 4 : 7,
                  child: Container(
                    width: compact ? 7 : 10,
                    height: compact ? 7 : 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: light ? AppColors.tealDark : AppColors.tealDark,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 9 : 13),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Yatra'),
                TextSpan(
                  text: 'Canvas',
                  style: TextStyle(
                    color: light ? Colors.white : AppColors.teal,
                  ),
                ),
              ],
            ),
            style: TextStyle(
              color: color,
              fontSize: compact ? 20 : 34,
              fontWeight: FontWeight.w800,
              letterSpacing: compact ? -0.75 : -1.4,
            ),
          ),
        ],
      ),
    );
  }
}
