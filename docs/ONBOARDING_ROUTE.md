# Route onboarding page

Verified: 2026-09-14. Status: `[IMPLEMENTED]` in Flutter widget, interaction, and visual tests.

## Redesign and Visual Architecture

Redesigned the third step of the YatraCanvas onboarding carousel to combine the photo-pin composition of coordinated Jaipur destinations with the minimal aqua surface and coordinated motion observed in `design_reference/` (`History - X.mp4`).

| Element | Journey Onboarding Implementation |
| --- | --- |
| Screen Background | Airy off-white screen (`#FFFFFF` to `#EFF3F8`), eliminating the saturated lower blue gradient while preserving branding and other steps |
| Composition Hierarchy | Branded header (logo + Skip) → Large rounded aqua travel illustration panel → Pagination indicator → Headline & description → Primary CTA ("Continue") |
| Aqua Surface | Soft cyan/aqua gradient (`#5CCDE6` to `#8DE3F4`), broad heavily diffused organic white highlights with subtle slow ambient drift (~10s cycle) |
| Route | Flowing continuous curved white route (`#FFFFFF`, width 4.2 px, round caps/joins, soft luminous outer glow) connecting three Jaipur destinations |
| Waypoints | Inactive: solid bright white dots with soft outer halo; Active/Selected: dark slate outlined ring (`#2C3E50`, width 3.5 px, diameter 22 px) with open aqua center |
| Photo Pins | Coordinated Jaipur landmarks from `lib/assets/home/jaipur.png`: **Amer Fort**, **Hawa Mahal**, and **Jal Mahal**. Soft rounded corners (18 px), fine milky border, subtle elevation shadow |
| Floating Badge | Translucent frosted capsule badge (`#FFFFFF` 90% opacity, 16 px corners) anchored adjacent to the active waypoint with horizontal slide & fade transitions |
| Interaction | Tapping any photo pin updates the shared selected-destination state, gently scaling the active photo (1.06x), moving the dark outlined ring marker, and transitioning the floating badge while keeping the route anchored |
| Motion | Progressive route reveal over ~1.25s entrance; sequential pin/waypoint reveals; gentle headline lift & fade; stationary anchored route during taps; full reduced-motion support |
| Copy | Heading: *"Beautiful places.\nOne seamless journey."*, Description: *"Discover places you love and bring them together in a trip that feels like you."* |

## Validation

- `flutter analyze`: zero issues found across all packages.
- `flutter test test/onboarding_screen_test.dart test/flow_updates_test.dart test/route_coverage_test.dart --no-pub`: all 11 tests pass.
- `flutter test --no-pub`: all 224 application tests pass.
- Responsive layout verified across small phones (320×640), standard (393×852), large (430×932), and landscape (844×390) at text scales 1.0 and 1.6.
- Interactive destination selection tested: Amer Fort, Hawa Mahal, Jal Mahal coordinate state cleanly. Rapid taps execute without overlap or jitter.
- Reduced-motion mode verified: presents instant completed route, stationary highlights, and instant selection.
- Visual baseline golden captured in `test/goldens/onboarding_screen_3.png`.
