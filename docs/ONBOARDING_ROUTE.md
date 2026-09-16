# Route onboarding page

Verified: 2026-09-15. Status: `[IMPLEMENTED]` in Flutter widget, interaction, and visual tests. Aligned with approved visual target (Image 1).

## Redesign and Visual Architecture

Redesigned the third step of the YatraCanvas onboarding carousel to match the approved visual target (Image 1), combining photographic speech-bubble destination pins, stylized aqua Jaipur map canvas, in-card header, and refined controls (circular Back button + Next pill button).

| Element | Journey Onboarding Implementation (Image 1 Aligned) |
| --- | --- |
| Screen Background | Clean white background (`#FFFFFF`), preserving authentic YatraCanvas branding and navigation flow |
| Composition Hierarchy | Branded header (centered logo + right Skip pill) → Large rounded aqua travel map card → Pagination indicator (4 naked dots) → Centered headline & description → Bottom controls (circular Back + Next pill) |
| Aqua Map Surface | Soft cyan/aqua gradient (`#DDF4FA` to `#50CBE5`), Jaipur street road grid overlay, sky blue lake water body, and diffused organic white highlights with subtle slow ambient drift (~10s cycle) |
| In-Card Header | Bold title: **Explore** (`#0F2537`) **Jaipur** (`#0284C7`), subtitle: *Places connect stories* (`#5A7A8E`, tracking 1.3) |
| Route | Flowing continuous curved white route (`#FFFFFF`, width 4.5 px, round caps/joins, soft luminous outer glow 9 px) connecting destinations 1, 2, and 3 |
| Waypoints | Numbered circular badges: solid dark teal (`#154C5B`, diameter 24 px) with centered bold numbers (**1**, **2**, **3**) positioned directly at the beak tips of photo pins |
| Photo Pins | Three photographic travel pins using dedicated high-res photography (`lib/assets/home/`): **Amber Fort**, **City Palace**, and **Hawa Mahal**. Continuous rounded corners (19 px), downward speech-bubble beaks, crisp 3.2 px white border, subtle elevation shadow |
| Destination Badges | Attached white capsule pills identifying **Amber Fort** (bottom-right of pin 1), **City Palace** (bottom-right of pin 2), and **Hawa Mahal** (centered directly below waypoint 3) |
| Bottom Controls | Circular Back button (`56x56`, `#FFFFFF`, subtle outline, dark teal left arrow `←`) on the left (visible when page > 0) + Expanded Next pill button (`56px` height, `#134552`, white text "Next" + right arrow `→`) on the right |
| Interaction | Tapping any photo pin updates the shared selected-destination state, gently scaling the active photo (1.06x) while keeping the route line completely anchored and stationary |
| Motion | Progressive route reveal over ~1.25s entrance; sequential pin/waypoint reveals (stop 1 at 0.0, stop 2 at 0.35, stop 3 at 0.70); gentle headline lift & fade; stationary anchored route during taps; full reduced-motion support |
| Copy | Centered Heading: *"Beautiful places.\nOne seamless journey."*, Centered Description: *"Discover places you love and bring them together in a trip that feels like you."* |

## Validation

- `flutter analyze lib test`: zero issues found across all packages.
- `flutter test test/onboarding_screen_test.dart test/flow_updates_test.dart test/route_coverage_test.dart --no-pub`: all 11 tests pass.
- Responsive layout verified across small phones (320×640), standard (393×852), large (430×932), and landscape (844×390) at text scales 1.0 and 1.6 with zero overflows.
- Interactive destination selection tested: Amber Fort, City Palace, Hawa Mahal coordinate state cleanly. Rapid taps execute without overlap or jitter.
- Reduced-motion mode verified: presents instant completed route, stationary highlights, and instant selection.
- Visual baseline golden captured in `test/goldens/onboarding_screen_3.png`.
