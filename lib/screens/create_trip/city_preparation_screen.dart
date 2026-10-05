import 'package:flutter/material.dart';

import '../../models/city.dart';
import '../../services/city_pack_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/primary_button.dart';

/// A real installation boundary with no artificial minimum display duration.
class CityPreparationScreen extends StatefulWidget {
  const CityPreparationScreen({
    required this.city,
    required this.next,
    this.repository,
    super.key,
  });
  final City city;
  final Widget next;
  final CityPackRepository? repository;
  @override
  State<CityPreparationScreen> createState() => _CityPreparationScreenState();
}

class _CityPreparationScreenState extends State<CityPreparationScreen> {
  String? _error;
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() => _error = null);
    try {
      final packs = widget.repository ?? CityPackRepository.shared;
      final places = await packs.getCityPlaces(widget.city.id!, limit: 6);
      if (!mounted) return;
      // A small first screenful only; image decoding never delays progression.
      for (final place in places.take(3)) {
        final image = place['image'];
        if (image is Map && image['thumbnail_asset_path'] is String) {
          precacheImage(
            AssetImage(image['thumbnail_asset_path'] as String),
            context,
            onError: (_, _) {},
          );
        }
      }
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute<void>(builder: (_) => widget.next));
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'The bundled city pack could not be prepared. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(backgroundColor: Colors.transparent),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.offline_pin_outlined,
              size: 48,
              color: AppColors.teal,
            ),
            const SizedBox(height: 28),
            Text(
              'Preparing ${widget.city.name} for you',
              style: AppTextStyles.pageTitle,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Getting your places, photos and trip planning ready for offline use.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 32),
            if (_error == null)
              const LinearProgressIndicator()
            else
              PrimaryButton(label: 'Try again', onPressed: _prepare),
          ],
        ),
      ),
    ),
  );
}
