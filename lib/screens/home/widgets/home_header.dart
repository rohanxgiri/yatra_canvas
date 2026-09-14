import 'package:flutter/material.dart';

import 'home_style.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.scale,
    required this.onProfile,
    this.name = 'Traveller',
    super.key,
  });
  final double scale;
  final String name;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back',
              style: HomeStyle.text(
                64 * scale,
                color: HomeStyle.ink,
                weight: FontWeight.w200,
              ),
            ),
            Text(
              name,
              style: HomeStyle.text(
                64 * scale,
                color: HomeStyle.ink,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.only(top: 19 * scale),
        child: HomeAction(
          label: 'Profile',
          onTap: onProfile,
          child: ClipOval(
            child: Container(
              width: 110 * scale,
              height: 112 * scale,
              color: const Color(0x66FFFFFF),
              alignment: Alignment.center,
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  HomeStyle.ink,
                  BlendMode.srcIn,
                ),
                child: HomeIcon(
                  'profile',
                  width: 48 * scale,
                  height: 48 * scale,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
