import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

class YatraBrand extends StatelessWidget {
  const YatraBrand({this.compact = false, this.light = false, super.key});

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : AppColors.charcoal;
    return Semantics(
      label: 'YatraCanvas',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 34 : 54,
            height: compact ? 34 : 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compact ? 10 : 17),
              border: Border.all(
                color: light ? Colors.white38 : AppColors.border,
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
            padding: EdgeInsets.all(compact ? 6 : 9),
            child: SvgPicture.asset('lib/Logo/logo.svg', fit: BoxFit.contain),
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
