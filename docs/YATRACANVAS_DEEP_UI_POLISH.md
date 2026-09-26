# YatraCanvas deep UI polish

Date: 2026-09-26

Status: `[IMPLEMENTED]` client presentation and interaction redesign;
`[PARTIAL]` traveler authentication and durable account ownership;
`[UNKNOWN]` release-profile performance on physical Android hardware.

This pass deliberately treats Home and Explore as the brand references and
redesigns weaker surfaces around their image-led travel character, cream-to-blue
canvas, route blue, calm typography, and restrained glass controls. It does not
change API contracts, provider behavior, planning algorithms, caching, database
schemas, migrations, or environment variables.

## Visual audit

The audit was performed against the implemented widgets, current tests, and the
393 px visual baselines. The repository does not contain the referenced
`design_reference/wanderlog/` directory, so no unavailable screenshot was
invented or treated as evidence.

| Surface | Before | Treatment | Result |
| --- | --- | --- | --- |
| Home | GOOD | Intentionally preserved | `[IMPLEMENTED]` protected reference |
| Explore | GOOD | Intentionally preserved | `[IMPLEMENTED]` protected reference |
| Onboarding opening | WEAK | Substantial redesign | Image-led editorial hero with concise display copy |
| Onboarding personalisation | POOR | Substantial redesign | Destination collage and travel-signal composition |
| Onboarding map | GOOD | Framing polish only | `[IMPLEMENTED]` original animation and concept preserved |
| Onboarding finish | WEAK | Substantial redesign | Calm itinerary story, clear primary action, lower-emphasis account entry |
| Authentication surfaces | WEAK | Light polish / honest routing | `[PARTIAL]` Google and traveler auth remain presentation-only; guest works |
| Destination selection / city search | POOR | Substantial redesign | Horizontal image-led inspiration and clearer search hierarchy |
| Date selection | WEAK | Substantial redesign | Destination/day-count/date hero above the calendar |
| Arrival / starting point | WEAK | Substantial redesign | Icon tiles with immediate selected state instead of utility chips |
| Interest selection | POOR | Substantial redesign | Two-column visual selection tiles, count feedback, strong selected state |
| Trip preferences / creation | WEAK | Noticeable redesign | Trip summary hero, predictable persistent CTA, clearer progressive hierarchy |
| Discover Places | WEAK | Substantial redesign | City image hero and content-first place cards |
| POI cards | WEAK | Substantial redesign | 16:10 image region, overlay category, compact details and save state |
| POI details | GOOD | Light polish through shared type/surface system | Existing editorial sheet preserved |
| Itinerary | POOR | Substantial redesign | Day-first story and schedule rather than expanded algorithm output |
| Day selector / rest / unscheduled | WEAK | Substantial redesign | Horizontal day cards, intentional rest copy, designed secondary warning section |
| Trip map | WEAK | Substantial redesign | Floating glass day controls replace AppBar popup chrome |
| Profile | POOR | Substantial redesign | Image-led identity hero and structured travel/account sections |
| Saved places | GOOD | Light polish through shared POI/type system | Existing image-led structure retained |
| Trip history empty state | WEAK | Substantial redesign | Editorial travel image, short headline, direct planning action |
| Trip summary | WEAK | Substantial redesign | Destination hero with dates, duration, purpose, origin, pace and transport |
| Settings | WEAK | Light polish | Clearer semantic hierarchy without turning settings into a decorative screen |
| Loading, empty and error states | WEAK | Noticeable polish | Stable skeletons retained; empty/error language and actions remain human and bounded |

## Screens substantially redesigned

- `[IMPLEMENTED]` Onboarding moments 1, 2, and 4 now form an editorial travel
  story around the protected map moment.
- `[IMPLEMENTED]` Destination, dates, arrival, interests, and preferences use
  exploratory or summary-led compositions instead of a sequence of form rows.
- `[IMPLEMENTED]` Discover uses a destination hero and image-dominant POI cards.
- `[IMPLEMENTED]` The itinerary exposes one selected day at a time with a custom
  horizontal selector; full, light, and rest days remain represented.
- `[IMPLEMENTED]` The map uses a floating glass day rail and keeps the base map
  immersive while retaining filtering and fit-to-bounds behavior.
- `[IMPLEMENTED]` Profile, trip history, and trip summary use travel imagery as
  meaningful hierarchy rather than decorative thumbnails.

## Screens lightly polished

- `[IMPLEMENTED]` POI details, Saved, day settings, Settings, auth forms,
  skeletons, empty states, and error states inherit the semantic type ramp,
  stronger surfaces, copy tone, and responsive behavior.
- `[PARTIAL]` Account Entry, Sign In, Sign Up, and Google controls accurately
  disclose that durable authentication is not yet connected. The functioning
  guest path remains available.

## Screens intentionally preserved

- `[IMPLEMENTED]` Home and Explore keep their accepted composition and identity.
- `[IMPLEMENTED]` The onboarding map animation, progressive route drawing,
  bundled map art, reduced-motion behavior, and animation concept are unchanged.
- `[IMPLEMENTED]` Backend-facing trip, recommendation, POI, map-route, cache,
  and scheduling behavior is unchanged.

## Typography system

The family is bundled `HomeInter`. Large type is regular rather than uniformly
semibold, with tight display leading and progressively more generous reading
leading. Supporting text stays readable at 14–15 sp rather than fading into tiny
grey copy. Deliberate wrapping is achieved by available width; accessibility text
scaling remains enabled.

| Semantic role | Size | Weight | Line height | Letter spacing |
| --- | ---: | ---: | ---: | ---: |
| Display | 40 | 400 | 1.06 | -1.15 |
| Page title | 34 | 400 | 1.10 | -0.90 |
| Section title | 22 | 600 | 1.18 | -0.45 |
| Card title | 18 | 600 | 1.25 | -0.25 |
| Body large | 16 | 400 | 1.50 | default |
| Body | 15 | 400 | 1.50 | default |
| Supporting | 14 | 400 | 1.45 | default |
| Label | 13 | 700 | 1.30 | 0.05 |
| Caption | 12 | 600 | 1.35 | default |
| Button | 16 | 700 | 1.20 | -0.05 |

## Color and surface system

- Canvas: `#F6F8FC`; warm canvas: `#FFFCF5`; soft blue surface: `#F0F6FF`.
- Primary route blue: `#055EC8`; deep route surface: `#164779`; selected:
  `#E7F0FF`.
- Editorial ink: `#141B34`; supporting text: `#5D687B`; tertiary text:
  `#8A94A6`.
- Accent is restrained to saffron `#F4B94F` and terracotta `#E86F51`.
- Success: `#278566`; error: `#B42318`; border: `#E1E6EF`; strong border:
  `#CDD5E2`.
- Solid white is used for readable content. Glass is limited to navigation,
  floating map controls, and compact contextual overlays. Image heroes use dark
  tonal gradients to guarantee text contrast.

## Spacing and composition system

- Core scale: 4, 8, 12, 16, 20, 24, 32, 40, and 48 logical pixels.
- Standard planning gutter: 20 px; editorial/account gutter: 24 px; readable
  content is centered and capped at 560 px on larger viewports.
- Content radius: 18–24 px; hero/sheet radius: 28–30 px; pills are reserved for
  actions, selectors, and compact metadata.
- Images use deliberate roles: destination/profile heroes, 16:10 POI media,
  compact itinerary symbols, and full-width empty-state art.
- Multi-step planning owns a persistent safe-area CTA surface so action placement
  stays predictable without covering scroll content.

## Button system

- Primary: solid route-blue stadium, 52 px minimum height, 16/700 label.
- Secondary: outlined/white surface with the same geometry and border token.
- Tertiary: text treatment for account entry, edit, and low-emphasis actions.
- Floating/glass: map and spatial controls only; selected map/day controls become
  solid deep-route surfaces.
- Disabled: `#DDE5EF` background with readable muted foreground.
- Touch targets remain at least 44–48 logical pixels and labels may grow or wrap
  under accessibility scaling.

## Motion system

- Instant: 100 ms; press: 130 ms; component state: 220 ms; navigation: 320 ms;
  journey completion: 380 ms.
- Standard easing: `easeOutCubic`; emphasized entrances: `easeOutQuart`; exits:
  `easeInCubic`.
- Onboarding uses page opacity/scale continuity and a 320 ms background gradient
  transition. Day switching uses a 240 ms `AnimatedSwitcher`; selection changes
  use short `AnimatedContainer` transitions.
- `MediaQuery.disableAnimations` reduces these transitions to zero duration.

## Major UX changes

- Destination selection now encourages exploration before requiring search.
- Dates communicate destination, length, and range before calendar mechanics.
- Arrival and interests provide strong, immediate selection feedback.
- The planning shell keeps progress, question, content, and next action in a
  stable order across all five steps.
- Discover places prioritizes imagery and useful context over metadata chips.
- The itinerary starts with day choice, then reveals that day's schedule. Rest
  days remain intentional and unscheduled places remain visible.
- Map day filtering is always visible in a compact floating rail instead of being
  hidden behind a popup menu.
- Profile and empty trip history now lead back into travel rather than presenting
  an administrative list or a large blank region.

## Onboarding redesign

The opening is now a single destination image with a restrained brand pill,
composed display heading, and one sentence. Personalisation uses a destination
collage and two travel signals instead of feature exposition. The existing map
animation remains the spacious third moment. The final screen explains the
shape of a calm day and keeps **Start Planning** dominant, with account entry as
a tertiary option. Skip and finish still enter guest mode and clear onboarding
from the route stack.

`[PARTIAL]` The account screen presents Google, create-account, sign-in, and guest
hierarchy, but Google/account submission still reports its planned state rather
than pretending authentication succeeded.

## Bugs fixed

- Removed narrow-phone and 160% text overflows in progress headers, interest
  tiles, Discover city heroes, itinerary metrics, onboarding heroes, and profile.
- Replaced fixed-height editorial columns with content-growing constraints where
  accessibility text requires additional height.
- Preserved semantic route/day copy while adapting tests to the visible custom day
  selector.
- Kept long destination names and planning questions wrap-safe without embedding
  test-breaking newline characters in their data strings.
- Kept off-screen interest selections reachable and testable through scrolling.
- Updated map tests from the removed popup control to the visible day rail.

## Performance considerations

- `[IMPLEMENTED]` No new network request, provider call, database read, or
  blocking navigation await was introduced.
- `[IMPLEMENTED]` Existing cache-first recommendations, image prefetching,
  stable placeholders, skeletons, background refresh, and optimistic selections
  are retained.
- `[IMPLEMENTED]` The map selector reuses the existing loaded route and only
  changes visible markers/polylines; it does not refetch route geometry.
- `[IMPLEMENTED]` Motion uses Flutter primitives and no new dependency. Glass is
  limited to one compact map overlay rather than repeated backdrop filters.
- `[IMPLEMENTED]` Large bundled destination images request viewport-sized decode
  widths in the redesigned collage and inspiration rail.
- `[UNKNOWN]` Physical-device decode cost and release-profile frame timing for the
  large bundled destination art still require representative Android hardware.

## Before and after validation

`[IMPLEMENTED]` The reviewed 393 px baselines are stored as repository evidence:

- Before: `docs/visual_checks/deep_ui_before/`
- After: `docs/visual_checks/deep_ui_after/`

The set covers four onboarding moments; destination, dates, arrival, interests,
and preferences; itinerary, day settings, and POI details; profile, saved,
settings, and history; plus the shared place-image/card system. Map behavior is
validated by widget tests for markers, route geometry, floating day filtering,
empty/light days, route failures, rest-day move exclusions, and status updates.

## Tests

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter compact`: **285 tests passed**.
- Visual suites pass for onboarding, planning, itinerary/POI/day settings,
  account screens, Home, Explore, and the shared place image system.
- Responsive coverage includes 320 and 393 px phones, 160% text scaling,
  landscape onboarding, 360/432/543 px map references, reduced motion, scrolling,
  and safe-area behavior.
- The test run emits flutter_map's standard public OpenStreetMap tile warning and
  two non-fatal off-screen-tap warnings in `select_dates_test.dart`; no test fails.

## Remaining issues

- `[PARTIAL]` Traveler sign-in, registration, Google OAuth, ownership binding,
  durable profile/trip history, and cross-device sync remain planned backend work.
- `[UNKNOWN]` TalkBack order, IME behavior, offline map tiles, and release-profile
  60 fps need verification on representative physical Android devices.
- `[UNKNOWN]` The application currently documents and validates the light visual
  system; a product-approved dark palette and dark-mode image treatment do not
  exist in the source-of-truth documents.
- `[PLANNED]` The two off-screen calendar taps in `select_dates_test.dart` should
  be migrated to `ensureVisible` in a dedicated test-maintenance change.
