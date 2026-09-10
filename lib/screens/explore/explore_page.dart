import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../home/widgets/home_destination_card.dart';
import '../home/widgets/home_style.dart';
import '../home/widgets/yatra_refractive_glass.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    required this.favorites,
    required this.onFavorite,
    required this.onOpenTripCreation,
    super.key,
  });

  final Set<String> favorites;
  final ValueChanged<String> onFavorite;
  final VoidCallback onOpenTripCreation;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  late final PageController _controller;
  int _selectedPage = 1;

  static const _categories = <ExploreCategory>[
    ExploreCategory(
      title: 'Nature Retreats',
      phrase: 'Room to breathe, trails to follow',
      asset: 'jaipur',
    ),
    ExploreCategory(
      title: 'Spiritual Journeys',
      phrase: 'Sacred places and slower moments',
      asset: 'ujjain',
    ),
    ExploreCategory(
      title: 'Food Trails',
      phrase: 'Follow flavour through every lane',
      asset: 'varanasi',
    ),
    ExploreCategory(
      title: 'Mountain Escapes',
      phrase: 'Cool air and unhurried horizons',
      asset: 'jaipur',
    ),
    ExploreCategory(
      title: 'Hidden Gems',
      phrase: 'Take the road beyond the obvious',
      asset: 'varanasi',
    ),
    ExploreCategory(
      title: 'Heritage',
      phrase: 'Stories written into stone',
      asset: 'ujjain',
    ),
    ExploreCategory(
      title: 'Weekend Escapes',
      phrase: 'A small pause that feels far away',
      asset: 'jaipur',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: .82, initialPage: 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: _ExploreBackground()),
      SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final scale = ((width - 40) / 620).clamp(.5, 1.0);
            final contentPadding = (width * .057143).clamp(20.0, 40.0);
            final carouselWidth = math.min(width, 520.0);
            final carouselHeight = (carouselWidth * .75).clamp(286.0, 371.0);
            final headingSize = (width * .082).clamp(30.0, 52.0);
            return CustomScrollView(
              key: const ValueKey('explore-scroll'),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    62 * scale,
                    0,
                    math.max(158, 190 * scale),
                  ),
                  sliver: SliverList.list(
                    children: [
                      Align(
                        child: SizedBox(
                          width: (240 * scale).clamp(172.0, 240.0),
                          height: (58 * scale).clamp(48.0, 58.0),
                          child: YatraRefractiveGlass(
                            radius: 76,
                            blur: 1.4,
                            displacement: 1.6,
                            fill: const Color(0xD9055EC8),
                            borderColor: const Color(0x66FFFFFF),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const ColorFiltered(
                                  colorFilter: ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                  child: HomeIcon(
                                    'route_pin',
                                    width: 20,
                                    height: 22,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Get Inspired to Go',
                                  style: HomeStyle.text(
                                    (18 * scale).clamp(14.0, 18.0),
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 48 * scale),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: contentPadding + 8 * scale,
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: HomeStyle.text(
                              headingSize,
                              color: const Color(0xFF151515),
                              weight: FontWeight.w300,
                            ),
                            children: const [
                              TextSpan(text: 'Escape The Ordinary,\nExplore '),
                              TextSpan(
                                text: 'Something\nExtraordinary',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: 66 * scale),
                      Align(
                        child: SizedBox(
                          width: carouselWidth,
                          height: carouselHeight,
                          child: PageView.builder(
                            key: const ValueKey('explore-carousel'),
                            controller: _controller,
                            itemCount: _categories.length,
                            onPageChanged: (value) =>
                                setState(() => _selectedPage = value),
                            itemBuilder: (context, index) => AnimatedBuilder(
                              animation: _controller,
                              builder: (context, child) {
                                final page = _controller.hasClients
                                    ? (_controller.page ??
                                          _controller.initialPage.toDouble())
                                    : _controller.initialPage.toDouble();
                                final distance = (page - index).abs().clamp(
                                  0.0,
                                  1.0,
                                );
                                return Transform.scale(
                                  scale: 1 - .075 * distance,
                                  child: Opacity(
                                    opacity: 1 - .2 * distance,
                                    child: child,
                                  ),
                                );
                              },
                              child: ExploreCategoryCard(
                                category: _categories[index],
                                selected: _selectedPage == index,
                                onTap: widget.onOpenTripCreation,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 24 * scale),
                      Align(
                        child: YatraRefractiveGlass(
                          radius: 30,
                          blur: 1,
                          displacement: 1,
                          fill: const Color(0x18FFFFFF),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                _categories.length,
                                (index) => AnimatedContainer(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  width: index == _selectedPage ? 11 : 9,
                                  height: index == _selectedPage ? 11 : 9,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == _selectedPage
                                        ? Colors.white
                                        : const Color(0x99EAF2FF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 44 * scale),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: contentPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Popular Destinations',
                              style: HomeStyle.text(24 * scale),
                            ),
                            SizedBox(height: 14 * scale),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: HomeDestinationCard(
                                    name: 'Jaipur',
                                    region: 'Rajisthan',
                                    image: 'jaipur',
                                    favorite: widget.favorites.contains(
                                      'Jaipur',
                                    ),
                                    onTap: widget.onOpenTripCreation,
                                    onFavorite: () =>
                                        widget.onFavorite('Jaipur'),
                                  ),
                                ),
                                SizedBox(width: 20 * scale),
                                Expanded(
                                  child: HomeDestinationCard(
                                    name: 'Varanasi',
                                    region: 'Uttar Pradesh',
                                    image: 'varanasi',
                                    favorite: widget.favorites.contains(
                                      'Varanasi',
                                    ),
                                    onTap: widget.onOpenTripCreation,
                                    onFavorite: () =>
                                        widget.onFavorite('Varanasi'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class ExploreCategory {
  const ExploreCategory({
    required this.title,
    required this.phrase,
    required this.asset,
  });

  final String title;
  final String phrase;
  final String asset;
}

class ExploreCategoryCard extends StatelessWidget {
  const ExploreCategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ExploreCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: HomeAction(
      label: 'Explore ${category.title}',
      onTap: onTap,
      selected: selected,
      child: YatraRefractiveGlass(
        radius: 30,
        blur: selected ? 1.5 : .8,
        displacement: selected ? 3.2 : 1.4,
        fill: const Color(0x18FFFFFF),
        borderColor: selected
            ? const Color(0xD9FFFFFF)
            : const Color(0x80FFFFFF),
        borderWidth: selected ? 1.2 : .7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        '${HomeStyle.assetRoot}${category.asset}.png',
                        fit: BoxFit.cover,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00191919),
                              Color(0x00191919),
                              Color(0xA6191919),
                            ],
                            stops: [0, .52, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 15,
                        child: Text(
                          category.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: HomeStyle.text(27, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  category.phrase,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: HomeStyle.text(
                    15,
                    color: const Color(0xFF31415B),
                    weight: FontWeight.w300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ExploreBackground extends StatelessWidget {
  const _ExploreBackground();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFCF5),
          Color(0xFFF6F8FC),
          Color(0xFFD9E8FC),
          Color(0xFF8DBAF6),
          Color(0xFF5798F1),
        ],
        stops: [0, .2, .43, .7, 1],
      ),
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.72, -.88),
          radius: .72,
          colors: [Color(0x66FFF0B8), Color(0x00FFF0B8)],
        ),
      ),
    ),
  );
}
