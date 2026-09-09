import 'package:flutter/material.dart';

import 'home_style.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({required this.scale, required this.onProfile, super.key});
  final double scale;
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
              'Mekur',
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
            child: Image.asset(
              '${HomeStyle.assetRoot}avatar.png',
              width: 110 * scale,
              height: 112 * scale,
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    ],
  );
}
