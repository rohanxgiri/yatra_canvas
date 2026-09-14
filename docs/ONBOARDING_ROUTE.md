# Route onboarding page

Verified: 2026-09-13. Status: `[IMPLEMENTED]` in Flutter widget and visual tests.

## Existing flow and design audit

Inspected every file in `lib/screens/onboarding/`, the shared onboarding canvas,
brand, `YCStyle`, onboarding assets/provenance, and onboarding/navigation tests
before editing. Splash opens the carousel; Welcome and Personal Interests are
compatibility wrappers. Login offers guest entry into the same carousel. The old
multi-step screenshots in `docs/screenshots/` do not represent the active flow.
The documented `design_reference/wanderlog/` directory was absent. The supplied
reference informed only the route/numbered-stop concept.

| Element | Active onboarding source of truth |
| --- | --- |
| Background | `OnboardingStyle.backgroundGradient`: cream through pale blue to travel blue, with existing warm radial glow |
| Palette | Ink `#141B34`, muted body `#526077`, blue `#055EC8`; existing pale blue and amber accents |
| Headings | Bundled HomeInter, 34 px, weight 300, height 1.16, zero added tracking; left aligned |
| Body | `YCStyle.body`: HomeInter, 16 px, weight 400, height 1.45; muted colour |
| Captions | `YCStyle.caption`: 12 px; no new font or type scale |
| Story layout | Shared `_Story`; 24 px horizontal padding, 16 px top, 14 px heading/body gap, 28 px before illustration; vertical scrolling |
| Artwork | Existing custom painterly Indian journey, `journey_editorial.png`; rounded 24 px clipping |
| Surfaces | White preview surfaces, 24 px corners, white border; no card shadow or backdrop blur in active story content |
| Primary button | Existing `OnboardingPrimaryButton`, full width, 52 px minimum height, stadium shape, blue fill, white medium-weight text, rounded forward icon |
| Skip | Existing `OnboardingGhostButton` / `HomeAction`, muted text, 14/10 px padding and press feedback |
| Back | Swipe to previous page; the current carousel has no separate Back control |
| Pagination | Existing translucent bordered capsule, 22×7 active pill and 7×7 inactive dots, 240 ms transition; now four positions |
| Motion | Existing 340 ms ease-out-cubic page navigation, zero-duration navigation when reduced motion is enabled; static story illustrations |
| Constraints | `SafeArea`, 600 px maximum content width, width-scaled outer controls, scrollable story content, fixed bottom controls |

## New page

Sequence: Discover → Personalise → **Route** → Itinerary → Home.
The new page explains how selected places connect before the final page introduces
the day-by-day pace. It shares `_Story`, typography, gradients, navigation and
pagination. Existing story content is unchanged.

The signature visual is one continuous blue road connecting three numbered stops:
Palace, Café and Ghats. The café uses the existing blue selection colour. Each card
uses a detail crop of the existing onboarding artwork through the extracted
`OnboardingJourneyImage`; no downloaded stock imagery or new bitmap is required.
The map uses pale blocks, white roads, small courtyard shapes and a quiet river.
All geometry and anchors are proportional to available width/height. Map height
also accommodates enlarged labels. This is an illustrative journey, not a named
city's geographic map or live routing result. It makes no network/location calls.

The complete image has a screen-reader description of the stop sequence. Individual
decorative image/number semantics are excluded. Labels respect system text scaling;
the numbered symbols remain legible at a bounded size. No new animation is added.

## Validation

- `dart analyze lib/screens/onboarding test/onboarding_screen_test.dart test/route_coverage_test.dart`: no issues.
- `flutter test test/onboarding_screen_test.dart test/flow_updates_test.dart test/route_coverage_test.dart --no-pub`: nine tests pass, including golden comparisons.
- Four-page order, Continue, backward swipe, forward swipe, Skip from the new page,
  final Start Planning, splash, and legacy entry paths verified.
- Rendered at 320×640, 393×852, 430×932 and 844×390, each at text scales 1.0 and 1.6,
  with simulated 28 px top and 24 px bottom safe areas. Short layouts scroll while
  the bottom action remains reachable. Route labels remain inside the illustration.
- Reviewed all four default pages side by side. Corrected the palace card's top
  clearance and shortened the riverside label to avoid word-breaking on small phones.
- Compared the top 700 px of the three original page renders against their existing
  pre-change test renders: pixel-identical content. Only the pagination gains a stop;
  the existing itinerary page moves from position three to four.
- Physical-device testing and release packaging were not performed for this change.

See [four-page comparison](visual_checks/onboarding_route_comparison.png).
The individual and responsive references are in `test/goldens/onboarding*.png`.
