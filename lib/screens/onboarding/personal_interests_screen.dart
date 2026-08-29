import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/onboarding_canvas.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_header.dart';
import '../home/home_screen.dart';

/// Complete first-run personalisation journey. The original class name is
/// retained so the existing login and guest entry points remain stable.
class PersonalInterestsScreen extends StatefulWidget {
  const PersonalInterestsScreen({super.key});

  @override
  State<PersonalInterestsScreen> createState() =>
      _PersonalInterestsScreenState();
}

class _PersonalInterestsScreenState extends State<PersonalInterestsScreen> {
  static const _stepCount = 10;
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController(text: 'Traveller');
  final Set<String> _challenges = {};
  final Set<String> _goals = {};
  int _step = 0;
  String _language = 'English';
  String? _planningStyle;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
    0 => _language.isNotEmpty,
    2 => _planningStyle != null,
    3 => _challenges.isNotEmpty,
    4 => _goals.isNotEmpty,
    9 => _name.text.trim().isNotEmpty,
    _ => true,
  };

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step == _stepCount - 1) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (route) => false,
      );
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      _pages.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _skip() => _pages.animateToPage(
    _stepCount - 1,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: Column(
            children: [
              ProgressHeader(
                currentStep: _step + 1,
                totalSteps: _stepCount,
                useSafeArea: false,
                onBack: _back,
                onSkip: _step >= 2 && _step < 8 ? _skip : null,
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (value) => setState(() => _step = value),
                  children: [
                    _languageStep(),
                    _welcomeStep(),
                    _planningStep(),
                    _challengeStep(),
                    _goalStep(),
                    _itineraryStep(),
                    _memoryStep(),
                    _comparisonStep(),
                    _featureStep(),
                    _profileStep(),
                  ],
                ),
              ),
              _BottomBar(
                child: PrimaryButton(
                  label: switch (_step) {
                    1 => 'Let’s Personalise',
                    8 => 'Set Up My Profile',
                    9 => 'Enter YatraCanvas',
                    _ => 'Continue',
                  },
                  icon: _step == 9
                      ? Icons.explore_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _canContinue ? _next : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageStep() {
    const languages = ['English', 'हिन्दी', 'বাংলা', 'தமிழ்', 'मराठी'];
    return _StepScroll(
      eyebrow: 'MAKE IT YOURS',
      title: 'Choose your\ntravel language',
      subtitle: 'Pick the language you’d like to use while planning journeys.',
      children: [
        for (final language in languages)
          _ChoiceCard(
            icon: language == 'English' ? '🌏' : 'अ',
            label: language,
            selected: _language == language,
            onTap: () => setState(() => _language = language),
          ),
      ],
    );
  }

  Widget _welcomeStep() => const _StepScroll(
    centered: true,
    children: [
      SizedBox(height: 48),
      _JourneyMedallion(),
      SizedBox(height: 34),
      Text(
        'Namaste, traveller!',
        textAlign: TextAlign.center,
        style: AppTextStyles.display,
      ),
      SizedBox(height: 12),
      Text(
        'A few quick choices will help us shape YatraCanvas around the way you travel.',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyLarge,
      ),
    ],
  );

  Widget _planningStep() {
    const options = [
      ('😊', 'I already have a good system'),
      ('🙂', 'It works, but feels scattered'),
      ('🫠', 'I’d love to make it easier'),
      ('🧭', 'I usually start without a plan'),
    ];
    return _StepScroll(
      eyebrow: 'YOUR TRAVEL STYLE',
      title: 'How does trip planning feel today?',
      children: [
        for (final item in options)
          _ChoiceCard(
            icon: item.$1,
            label: item.$2,
            selected: _planningStyle == item.$2,
            onTap: () => setState(() => _planningStyle = item.$2),
          ),
      ],
    );
  }

  Widget _challengeStep() => _multiChoice(
    eyebrow: 'CHOOSE ALL THAT APPLY',
    title: 'What are the hardest parts of planning?',
    selected: _challenges,
    options: const [
      ('🔎', 'Too much time spent researching'),
      ('🌀', 'Sorting through too many options'),
      ('🏷️', 'Knowing what is truly worth it'),
      ('🗂️', 'Keeping plans in one place'),
      ('🚆', 'Transport and stays'),
      ('⏱️', 'Building a well-paced itinerary'),
    ],
  );

  Widget _goalStep() => _multiChoice(
    eyebrow: 'YOUR YATRACANVAS',
    title: 'What would make travel planning better?',
    selected: _goals,
    options: const [
      ('⚡', 'Plan trips faster, with less stress'),
      ('📍', 'Find places that feel personal'),
      ('🗂️', 'Keep every detail organised'),
      ('🗓️', 'Build a complete itinerary'),
      ('👥', 'Plan together with friends'),
      ('🗺️', 'Remember places I have visited'),
    ],
  );

  Widget _multiChoice({
    required String eyebrow,
    required String title,
    required Set<String> selected,
    required List<(String, String)> options,
  }) => _StepScroll(
    eyebrow: eyebrow,
    title: title,
    children: [
      for (final item in options)
        _ChoiceCard(
          icon: item.$1,
          label: item.$2,
          selected: selected.contains(item.$2),
          onTap: () => setState(() {
            if (!selected.add(item.$2)) selected.remove(item.$2);
          }),
        ),
    ],
  );

  Widget _itineraryStep() => const _StepScroll(
    centered: true,
    eyebrow: 'ONE CLEAR PLAN',
    title: 'Turn saved ideas into a day that flows',
    subtitle: 'See every stop, travel time, and booking together—without juggling tabs.',
    children: [_MiniItinerary()],
  );

  Widget _memoryStep() => const _StepScroll(
    centered: true,
    eyebrow: 'TRAVEL, REMEMBERED',
    title: 'Plans feel better when everyone has a voice',
    subtitle: 'Keep notes, reactions, and shared favourites beside the places they belong.',
    children: [_MemoryStack()],
  );

  Widget _comparisonStep() => const _StepScroll(
    centered: true,
    eyebrow: 'LESS ADMIN, MORE YATRA',
    title: 'Your whole trip, finally in one place',
    children: [_ComparisonPanel()],
  );

  Widget _featureStep() => const _StepScroll(
    centered: true,
    eyebrow: 'READY FOR THE ROAD',
    title: 'Built to guide you from idea to itinerary',
    children: [
      _FeatureTile(
        Icons.cloud_done_outlined,
        'Offline-ready plans',
        'Keep essential details close even when signal is not.',
      ),
      _FeatureTile(
        Icons.auto_awesome_rounded,
        'Thoughtful assistance',
        'Get help shaping a trip around your pace.',
      ),
      _FeatureTile(
        Icons.alt_route_rounded,
        'Clear route planning',
        'See travel time between stops before the day begins.',
      ),
      _FeatureTile(
        Icons.groups_2_outlined,
        'Shared decisions',
        'Collect ideas and plan together.',
      ),
    ],
  );

  Widget _profileStep() => _StepScroll(
    centered: true,
    eyebrow: 'ONE LAST DETAIL',
    title: 'Set up your travel profile',
    subtitle: 'You can change this any time from your profile.',
    children: [
      const _ProfileAvatar(),
      const SizedBox(height: 20),
      TextField(
        controller: _name,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Display name',
          hintText: 'How should we greet you?',
          prefixIcon: Icon(Icons.person_outline_rounded),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'By continuing, you agree to the Terms of Use and Privacy Policy.',
        textAlign: TextAlign.center,
        style: AppTextStyles.caption,
      ),
    ],
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: const BoxDecoration(
      color: Color(0xF2FFFFFF),
      boxShadow: [
        BoxShadow(
          color: Color(0x10142033),
          blurRadius: 22,
          offset: Offset(0, -6),
        ),
      ],
    ),
    child: child,
  );
}

class _StepScroll extends StatelessWidget {
  const _StepScroll({
    this.eyebrow,
    this.title,
    this.subtitle,
    this.centered = false,
    this.children = const [],
  });
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final bool centered;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
        child: Column(
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(
                eyebrow!,
                textAlign: centered ? TextAlign.center : TextAlign.left,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (title != null) ...[
              Text(
                title!,
                textAlign: centered ? TextAlign.center : TextAlign.left,
                style: AppTextStyles.display,
              ),
              const SizedBox(height: 12),
            ],
            if (subtitle != null) ...[
              Text(
                subtitle!,
                textAlign: centered ? TextAlign.center : TextAlign.left,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 26),
            ] else if (title != null)
              const SizedBox(height: 22),
            ...children.map(
              (child) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.tealLight : Colors.white,
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            border: Border.all(
              color: selected ? AppColors.teal : Colors.white,
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0E142033),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: Text(icon, style: const TextStyle(fontSize: 25)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppTextStyles.cardTitle)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('on'),
                        color: AppColors.teal,
                      )
                    : const Icon(
                        Icons.circle_outlined,
                        key: ValueKey('off'),
                        color: AppColors.borderStrong,
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _JourneyMedallion extends StatelessWidget {
  const _JourneyMedallion();

  @override
  Widget build(BuildContext context) => Container(
    width: 176,
    height: 176,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .84),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [
        BoxShadow(
          color: Color(0x20315EEB),
          blurRadius: 30,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: const Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.public_rounded, size: 104, color: AppColors.tealLight),
        Icon(Icons.route_rounded, size: 84, color: AppColors.teal),
        Positioned(
          right: 32,
          top: 34,
          child: Icon(
            Icons.location_on_rounded,
            color: AppColors.terracotta,
            size: 36,
          ),
        ),
      ],
    ),
  );
}

class _MiniItinerary extends StatelessWidget {
  const _MiniItinerary();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _panelDecoration(),
    child: const Column(
      children: [
        _PlanStop(
          '1',
          Icons.temple_hindu_rounded,
          'City Palace',
          '9:30 AM · 90 min',
        ),
        _TravelLine('12 min · 2.4 km'),
        _PlanStop(
          '2',
          Icons.restaurant_rounded,
          'Old City lunch',
          '12:15 PM · Local favourite',
        ),
        _TravelLine('8 min · walk'),
        _PlanStop(
          '3',
          Icons.shopping_bag_outlined,
          'Artisan bazaar',
          '2:00 PM · Flexible',
        ),
      ],
    ),
  );
}

class _PlanStop extends StatelessWidget {
  const _PlanStop(this.number, this.icon, this.title, this.detail);
  final String number;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(19),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          child: Text(
            number,
            style: AppTextStyles.label.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: AppColors.terracotta),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.cardTitle),
              Text(detail, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TravelLine extends StatelessWidget {
  const _TravelLine(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const SizedBox(width: 19),
        Container(width: 2, height: 26, color: AppColors.tealLight),
        const SizedBox(width: 28),
        const Icon(
          Icons.directions_walk_rounded,
          size: 17,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.caption),
      ],
    ),
  );
}

class _MemoryStack extends StatelessWidget {
  const _MemoryStack();

  @override
  Widget build(BuildContext context) {
    const places = [
      (
        'Hawa Mahal',
        'A perfect early-morning stop',
        Icons.temple_hindu_rounded,
        AppColors.terracotta,
      ),
      (
        'Albert Hall',
        'Save this for sunset',
        Icons.account_balance_rounded,
        AppColors.teal,
      ),
      (
        'Nahargarh Fort',
        'Everyone voted yes',
        Icons.fort_rounded,
        AppColors.emerald,
      ),
    ];
    return Column(
      children: [
        for (final place in places)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: _panelDecoration(radius: 22),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: place.$4.withValues(alpha: .12),
                  foregroundColor: place.$4,
                  child: Icon(place.$3),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.$1, style: AppTextStyles.cardTitle),
                      Text(place.$2, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                const Text('❤️ 3', style: AppTextStyles.caption),
              ],
            ),
          ),
      ],
    );
  }
}

class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel();

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: _panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.surfaceSoft,
              child: const _CompareColumn('Scattered planning', false, [
                'Tabs and screenshots',
                'Details in many apps',
                'More logistics to track',
              ]),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: const _CompareColumn('YatraCanvas', true, [
                'Ideas become a route',
                'One shared plan',
                'More time for the trip',
              ]),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CompareColumn extends StatelessWidget {
  const _CompareColumn(this.title, this.good, this.points);
  final String title;
  final bool good;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.emerald : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.cardTitle.copyWith(
            color: good ? AppColors.teal : AppColors.charcoal,
          ),
        ),
        const SizedBox(height: 18),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  good ? Icons.check_rounded : Icons.close_rounded,
                  color: color,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    point,
                    style: AppTextStyles.body.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _panelDecoration(radius: 22),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.tealLight,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(icon, color: AppColors.teal),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.cardTitle),
              const SizedBox(height: 4),
              Text(body, style: AppTextStyles.bodyMuted),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Container(
        width: 158,
        height: 158,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD991), Color(0xFFF49C84), Color(0xFF315EEB)],
          ),
        ),
        child: const Icon(Icons.hiking_rounded, color: Colors.white, size: 76),
      ),
      Positioned(
        right: 2,
        bottom: 5,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.edit_rounded, color: AppColors.teal),
        ),
      ),
    ],
  );
}

BoxDecoration _panelDecoration({double radius = 28}) => BoxDecoration(
  color: const Color(0xF2FFFFFF),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white),
  boxShadow: const [
    BoxShadow(color: Color(0x14142033), blurRadius: 22, offset: Offset(0, 10)),
  ],
);
