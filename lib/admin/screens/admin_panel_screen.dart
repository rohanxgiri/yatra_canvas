import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _selectedIndex = 0;

  static const _sections = <_AdminSection>[
    _AdminSection('Overview', Icons.space_dashboard_rounded),
    _AdminSection('Trips', Icons.route_rounded),
    _AdminSection('Destinations', Icons.location_city_rounded),
    _AdminSection('Travellers', Icons.people_alt_rounded),
    _AdminSection('Reports', Icons.flag_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= 920;
        return Scaffold(
          drawer: showSidebar
              ? null
              : Drawer(
                  width: 280,
                  child: SafeArea(child: _buildSidebar(closeAfterTap: true)),
                ),
          body: Row(
            children: [
              if (showSidebar)
                SizedBox(
                  width: 264,
                  child: _buildSidebar(closeAfterTap: false),
                ),
              Expanded(
                child: ColoredBox(
                  color: AppColors.canvas,
                  child: SafeArea(
                    child: Column(
                      children: [
                        _AdminTopBar(
                          title: _sections[_selectedIndex].label,
                          showMenu: !showSidebar,
                          onMenuPressed: () =>
                              Scaffold.of(context).openDrawer(),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              constraints.maxWidth < 700 ? 16 : 28,
                              12,
                              constraints.maxWidth < 700 ? 16 : 28,
                              40,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1440),
                              child: _buildPage(_selectedIndex),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar({required bool closeAfterTap}) {
    return ColoredBox(
      color: AppColors.tealDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 20, 30),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white54),
                  ),
                  padding: const EdgeInsets.all(7),
                  child: SvgPicture.asset(
                    'lib/Logo/logo.svg',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YatraCanvas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ADMIN STUDIO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: List.generate(_sections.length, (index) {
                final section = _sections[index];
                final selected = index == _selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: selected
                        ? Colors.white.withValues(alpha: .12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      selected: selected,
                      leading: Icon(
                        section.icon,
                        color: selected ? AppColors.marigold : Colors.white70,
                      ),
                      title: Text(
                        section.label,
                        style: AppTextStyles.label.copyWith(
                          color: selected ? Colors.white : Colors.white70,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        if (closeAfterTap) Navigator.of(context).pop();
                      },
                    ),
                  ),
                );
              }),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.marigold,
                    foregroundColor: AppColors.tealDark,
                    child: Text('AK'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aarav Kumar',
                          style: AppTextStyles.label.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Administrator',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_horiz_rounded, color: Colors.white54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    return switch (index) {
      0 => const _OverviewPage(),
      1 => const _TripsPage(),
      2 => const _DestinationsPage(),
      3 => const _TravellersPage(),
      _ => const _ReportsPage(),
    };
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.title,
    required this.showMenu,
    required this.onMenuPressed,
  });

  final String title;
  final bool showMenu;
  final VoidCallback onMenuPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (showMenu) ...[
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Open navigation',
            ),
            const SizedBox(width: 8),
          ],
          Text(title, style: AppTextStyles.sectionTitle),
          const Spacer(),
          SizedBox(
            width: MediaQuery.sizeOf(context).width > 760 ? 280 : 48,
            child: MediaQuery.sizeOf(context).width > 760
                ? TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search anything',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isEmpty) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Searching for “$value”')),
                      );
                    },
                  )
                : IconButton.filledTonal(
                    onPressed: () {},
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search',
                  ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            onPressed: () {},
            icon: const Badge(
              smallSize: 7,
              child: Icon(Icons.notifications_none_rounded),
            ),
            tooltip: 'Notifications',
          ),
        ],
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage();

  static const metrics = <_MetricData>[
    _MetricData(
      'Active travellers',
      '2,840',
      '+12.4%',
      Icons.people_alt_rounded,
    ),
    _MetricData('Trips this month', '1,284', '+8.2%', Icons.route_rounded),
    _MetricData('Destinations', '86', '+6 new', Icons.location_city_rounded),
    _MetricData('Open reports', '14', 'Needs review', Icons.flag_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Good morning, Aarav', style: AppTextStyles.pageTitle),
        const SizedBox(height: 6),
        Text(
          'Here is what is happening across YatraCanvas today.',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1120
                ? 4
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - ((columns - 1) * 14)) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: metrics
                  .map(
                    (metric) =>
                        SizedBox(width: width, child: _MetricCard(metric)),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 960;
            final routePulse = const _RoutePulseCard();
            final attention = const _AttentionCard();
            if (stacked) {
              return Column(
                children: [routePulse, SizedBox(height: 16), attention],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: routePulse),
                SizedBox(width: 16),
                Expanded(flex: 4, child: attention),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const _RecentTripsCard(),
      ],
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.change, this.icon);

  final String label;
  final String value;
  final String change;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.data);

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final warning = data.label == 'Open reports';
    return _PanelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (warning ? AppColors.terracotta : AppColors.teal)
                      .withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  data.icon,
                  color: warning ? AppColors.terracotta : AppColors.teal,
                ),
              ),
              const Spacer(),
              Text(
                data.change,
                style: AppTextStyles.caption.copyWith(
                  color: warning ? AppColors.terracotta : AppColors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(data.value, style: AppTextStyles.pageTitle),
          const SizedBox(height: 4),
          Text(data.label, style: AppTextStyles.bodyMuted),
        ],
      ),
    );
  }
}

class _RoutePulseCard extends StatelessWidget {
  const _RoutePulseCard();

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            title: 'Route pulse',
            subtitle: 'Trips created over the last seven days',
            trailing: _StatusPill('LIVE', color: AppColors.success),
          ),
          SizedBox(
            height: 258,
            width: double.infinity,
            child: CustomPaint(
              painter: _RoutePulsePainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        _PulseLegend('Mon', '142'),
                        _PulseLegend('Tue', '176'),
                        _PulseLegend('Wed', '158'),
                        _PulseLegend('Thu', '224'),
                        _PulseLegend('Fri', '198'),
                        _PulseLegend('Sat', '268'),
                        _PulseLegend('Sun', '242'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = AppColors.border;
    for (var i = 1; i < 5; i++) {
      final y = 32.0 + (i * 36);
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), grid);
    }

    final points = <Offset>[
      Offset(32, 142),
      Offset(size.width * .18, 118),
      Offset(size.width * .34, 130),
      Offset(size.width * .5, 78),
      Offset(size.width * .65, 98),
      Offset(size.width * .82, 46),
      Offset(size.width - 32, 66),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midpoint = (previous.dx + current.dx) / 2;
      path.cubicTo(
        midpoint,
        previous.dy,
        midpoint,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, 174)
      ..lineTo(points.first.dx, 174)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x35315EEB), Color(0x00315EEB)],
        ).createShader(Rect.fromLTWH(0, 32, size.width, 150)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.teal
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = AppColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulseLegend extends StatelessWidget {
  const _PulseLegend(this.day, this.value);

  final String day;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          day,
          style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard();

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        children: [
          const _CardHeader(
            title: 'Needs attention',
            subtitle: 'Items waiting for review',
          ),
          const _AttentionItem(
            icon: Icons.flag_rounded,
            color: AppColors.terracotta,
            title: '5 new reports',
            subtitle: 'Two marked high priority',
          ),
          const Divider(),
          const _AttentionItem(
            icon: Icons.place_rounded,
            color: AppColors.marigold,
            title: '8 place updates',
            subtitle: 'Submitted by travellers',
          ),
          const Divider(),
          const _AttentionItem(
            icon: Icons.image_not_supported_rounded,
            color: AppColors.teal,
            title: '3 missing photos',
            subtitle: 'Featured destinations',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: () {},
              child: const Text('Review queue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionItem extends StatelessWidget {
  const _AttentionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _RecentTripsCard extends StatelessWidget {
  const _RecentTripsCard();

  static const rows = <_TripRow>[
    _TripRow('Ujjain Spiritual Trail', 'Meera Shah', '25–27 Aug', 'Planning'),
    _TripRow('Jaipur Heritage Weekend', 'Rohan Joshi', '29–31 Aug', 'Ready'),
    _TripRow('Monsoon in Goa', 'Ananya Rao', '03–07 Sep', 'Planning'),
    _TripRow('Manali Slow Escape', 'Kabir Singh', '10–15 Sep', 'Confirmed'),
  ];

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            title: 'Recent trips',
            subtitle: 'Latest plans created by travellers',
          ),
          ...rows.map((trip) => _TripListTile(trip: trip)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TripsPage extends StatelessWidget {
  const _TripsPage();

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      eyebrow: 'TRIP OPERATIONS',
      title: 'Traveller journeys',
      subtitle: 'Review current plans and their progress.',
      actionLabel: 'Export trips',
      actionIcon: Icons.download_rounded,
      filters: const ['All trips', 'Planning', 'Ready', 'Confirmed'],
      children: _RecentTripsCard.rows
          .map((trip) => _TripListTile(trip: trip, detailed: true))
          .toList(),
    );
  }
}

class _TripRow {
  const _TripRow(this.title, this.traveller, this.dates, this.status);

  final String title;
  final String traveller;
  final String dates;
  final String status;
}

class _TripListTile extends StatelessWidget {
  const _TripListTile({required this.trip, this.detailed = false});

  final _TripRow trip;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Opening ${trip.title}'))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.tealGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.route_rounded, color: Colors.white),
            ),
            const SizedBox(width: 13),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.title, style: AppTextStyles.label),
                  const SizedBox(height: 3),
                  Text(trip.traveller, style: AppTextStyles.caption),
                ],
              ),
            ),
            if (MediaQuery.sizeOf(context).width > 680) ...[
              Expanded(child: Text(trip.dates, style: AppTextStyles.bodyMuted)),
              SizedBox(width: 110, child: _StatusPill(trip.status)),
            ],
            if (detailed)
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_horiz_rounded),
                tooltip: 'More actions',
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _DestinationsPage extends StatelessWidget {
  const _DestinationsPage();

  static const destinations = <(String, String, String, IconData)>[
    ('Ujjain', 'Madhya Pradesh', '24 places', Icons.temple_hindu_rounded),
    ('Jaipur', 'Rajasthan', '38 places', Icons.fort_rounded),
    ('Goa', 'Konkan Coast', '42 places', Icons.beach_access_rounded),
    ('Manali', 'Himachal Pradesh', '31 places', Icons.landscape_rounded),
    ('Varanasi', 'Uttar Pradesh', '29 places', Icons.water_rounded),
    ('Udaipur', 'Rajasthan', '27 places', Icons.sailing_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      eyebrow: 'CONTENT LIBRARY',
      title: 'Destinations',
      subtitle: 'Manage the places travellers can discover.',
      actionLabel: 'Add destination',
      actionIcon: Icons.add_rounded,
      filters: const ['Published', 'Drafts', 'Needs review'],
      useGrid: true,
      children: destinations
          .map(
            (item) => _DestinationAdminCard(
              name: item.$1,
              region: item.$2,
              places: item.$3,
              icon: item.$4,
            ),
          )
          .toList(),
    );
  }
}

class _DestinationAdminCard extends StatelessWidget {
  const _DestinationAdminCard({
    required this.name,
    required this.region,
    required this.places,
    required this.icon,
  });

  final String name;
  final String region;
  final String places;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 112,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8EA8F8), AppColors.tealDark],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -12,
                  bottom: -16,
                  child: Icon(icon, size: 112, color: Colors.white24),
                ),
                Center(child: Icon(icon, size: 42, color: Colors.white)),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _StatusPill('Published', color: AppColors.success),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTextStyles.cardTitle),
                      const SizedBox(height: 3),
                      Text('$region • $places', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Edit $name'))),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit destination',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TravellersPage extends StatelessWidget {
  const _TravellersPage();

  static const travellers = <(String, String, String, String)>[
    ('MS', 'Meera Shah', 'meera@example.com', '12 trips'),
    ('RJ', 'Rohan Joshi', 'rohan@example.com', '8 trips'),
    ('AR', 'Ananya Rao', 'ananya@example.com', '5 trips'),
    ('KS', 'Kabir Singh', 'kabir@example.com', '11 trips'),
    ('NP', 'Nisha Patel', 'nisha@example.com', '3 trips'),
  ];

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      eyebrow: 'COMMUNITY',
      title: 'Travellers',
      subtitle: 'A simple view of people planning with YatraCanvas.',
      actionLabel: 'Export list',
      actionIcon: Icons.download_rounded,
      filters: const ['All travellers', 'Active', 'New this month'],
      children: travellers
          .map(
            (user) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: AppColors.tealLight,
                foregroundColor: AppColors.tealDark,
                child: Text(user.$1),
              ),
              title: Text(user.$2, style: AppTextStyles.label),
              subtitle: Text(user.$3, style: AppTextStyles.caption),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (MediaQuery.sizeOf(context).width > 620)
                    Text(user.$4, style: AppTextStyles.bodyMuted),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage();

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      eyebrow: 'REVIEW QUEUE',
      title: 'Reports',
      subtitle: 'Review content flagged by travellers.',
      actionLabel: 'Mark all reviewed',
      actionIcon: Icons.done_all_rounded,
      filters: const ['Open', 'High priority', 'Resolved'],
      children: const [
        _ReportTile(
          title: 'Incorrect opening hours',
          detail: 'Mahakaleshwar Temple • reported 18 min ago',
          priority: 'High',
        ),
        _ReportTile(
          title: 'Place is temporarily closed',
          detail: 'Nahargarh Fort • reported 2 hours ago',
          priority: 'Medium',
        ),
        _ReportTile(
          title: 'Duplicate destination photo',
          detail: 'Baga Beach • reported yesterday',
          priority: 'Low',
        ),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.title,
    required this.detail,
    required this.priority,
  });

  final String title;
  final String detail;
  final String priority;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.terracotta.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.flag_outlined, color: AppColors.terracotta),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.label),
                const SizedBox(height: 3),
                Text(detail, style: AppTextStyles.caption),
              ],
            ),
          ),
          _StatusPill(
            priority,
            color: priority == 'High'
                ? AppColors.terracotta
                : AppColors.marigold,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report marked as reviewed')),
            ),
            icon: const Icon(Icons.check_circle_outline_rounded),
            tooltip: 'Mark reviewed',
          ),
        ],
      ),
    );
  }
}

class _ManagementPage extends StatefulWidget {
  const _ManagementPage({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.filters,
    required this.children,
    this.useGrid = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final List<String> filters;
  final List<Widget> children;
  final bool useGrid;

  @override
  State<_ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<_ManagementPage> {
  int selectedFilter = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.eyebrow,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.teal,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 620,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AppTextStyles.pageTitle),
                  const SizedBox(height: 6),
                  Text(widget.subtitle, style: AppTextStyles.bodyMuted),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(widget.actionLabel))),
              icon: Icon(widget.actionIcon),
              label: Text(widget.actionLabel),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(widget.filters.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(widget.filters[index]),
                  selected: selectedFilter == index,
                  onSelected: (_) => setState(() => selectedFilter = index),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 18),
        if (widget.useGrid)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 3
                  : constraints.maxWidth >= 620
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 14)) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: widget.children
                    .map((child) => SizedBox(width: width, child: child))
                    .toList(),
              );
            },
          )
        else
          _PanelCard(
            child: Column(
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  widget.children[i],
                  if (i != widget.children.length - 1) const Divider(),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.cardTitle),
                const SizedBox(height: 3),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ??
        switch (label) {
          'Confirmed' => AppColors.success,
          'Ready' => AppColors.teal,
          _ => AppColors.marigold,
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTextStyles.caption.copyWith(
          color: resolvedColor == AppColors.marigold
              ? AppColors.charcoal
              : resolvedColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A14294E),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _AdminSection {
  const _AdminSection(this.label, this.icon);

  final String label;
  final IconData icon;
}
