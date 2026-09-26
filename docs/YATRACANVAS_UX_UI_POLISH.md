# YatraCanvas UX/UI polish

Date: 2026-09-24
Status: `[IMPLEMENTED]` repository polish and regression coverage; `[PARTIAL]`
traveler authentication and durable account state; `[UNKNOWN]` physical-device
performance until a device can be connected.

## Before

The repository already contained a substantial September 2026 UI redesign. Home,
Explore, the trip-creation flow, Discover, itinerary, map, POI details, account
surfaces, shared `YCStyle`/`YCScaffold` primitives, `YCMotion`, skeletons, reduced
motion handling, and visual regression tests were present. This pass therefore
treated the work as a product audit and convergence exercise instead of replacing
working screens.

The audit found the following concrete gaps:

- Onboarding ended at polished but non-functional account choices even though
  traveler authentication is `[PARTIAL]` and the working product path is guest
  mode.
- The legacy login route performed a one-frame redirect, producing a blank and
  confusing intermediate state.
- The profile upgrade strip and shared auth actions overflowed on a 320 px phone
  at 160% text scaling.
- Profile statistics disappeared when their value reached zero, changing the
  screen hierarchy and making the empty state harder to understand.
- Account screens contained a private copy of a state-card component already
  supplied by the shared scaffold system.
- A place whose normalized category was `other` could ignore a more meaningful
  raw `heritage` category and show the generic landscape fallback. Hawa Mahal was
  the visible example.
- A bundled fallback image could briefly paint an empty image region while the
  asset decoder produced its first frame.
- Several tests and goldens described older labels or layouts and no longer
  protected the current product behavior.

No API contract, provider integration, planner algorithm, cache policy, database
schema, migration, or environment variable was changed.

## Design language

Home and Explore remain the source of truth. The pass extracted and followed these
existing qualities:

- `HomeInter` typography with large, calm titles; compact supporting text; and
  strong label contrast.
- A navy/blue hierarchy on a cream-to-blue canvas, with solid readable content
  surfaces and restrained borders.
- A predictable 4/8-derived spacing rhythm, generous 20–24 px screen edges, and
  clear section separation.
- Rounded content cards without making every surface a pill; pill geometry is
  reserved for primary actions, navigation, chips, and compact controls.
- Image-led travel content, quiet shadows, and glass/translucency limited to
  navigation or genuinely floating controls.
- Comfortable controls around 48–56 logical pixels with immediate pressed-state
  feedback and responsive text rather than disabled text scaling.

Existing `YCStyle`, `YCScaffold`, shared state cards, buttons, navigation, image
components, and motion constants were reused. No second design system or visual
rebrand was introduced.

## Onboarding

`[IMPLEMENTED]` The existing four-moment story remains:

1. an emotional, image-led discovery introduction;
2. a visual expression of personal travel style;
3. the existing Jaipur map/route animation;
4. a practical, pace-aware readiness moment.

The final action is now **Start Planning**. Continue, swipe, Back, Skip, and the
progress indicator retain one consistent responsive shell. Finish and Skip both
enter `YatraSession` guest mode and clear the route stack to Home. This makes the
working path honest and prevents Back from returning to onboarding.

The map animation, bundled map assets, route drawing, progressive reveal,
composition, and reduced-motion behavior were preserved. A scale-aware button
layout keeps the exact standard-text geometry used by its protected goldens while
allowing the action to grow and wrap at enlarged system text sizes.

## Interaction system

The existing `YCMotion` interaction layer remains authoritative: short,
purposeful route transitions; press feedback; animated selection where it explains
state; and zero-duration/reduced-motion alternatives. This pass intentionally did
not add decorative loops or new animation dependencies.

The meaningful interaction changes are:

- onboarding completion is a one-way transition into the product instead of a
  dead-end account preview;
- the legacy login route now presents an explicit **Continue as Guest** action and
  accurately explains session-only storage;
- primary, Google, and guest auth buttons keep their fixed visual geometry at
  normal text sizes but grow and wrap above 130% text scaling;
- the profile upgrade prompt switches from a horizontal to a vertical composition
  when width or scaled text requires it, while retaining a native 44+ px action;
- image regions render a stable neutral placeholder until a local fallback frame
  is decoded, preventing a blank flash and layout ambiguity.

## Screens polished

The screens and surfaces modified in this pass were:

- onboarding navigation and completion behavior;
- legacy guest entry/login;
- account entry availability copy;
- Profile, Saved, History, and Settings account surfaces and their responsive
  shared account composition;
- shared onboarding/auth actions;
- POI/place image fallback presentation and semantics;
- itinerary and POI visual baselines where the implemented UI had outgrown stale
  reference images.

The following major surfaces were inspected through code, interaction tests, and
goldens without being redesigned: Home, Explore, destination/date/arrival/purpose/
preferences planning, Discover Places, itinerary/day planning, trip map, POI
details, saved/profile/settings states, auth forms, loading states, empty states,
and error states.

## Bugs fixed

| Symptom | Root cause | Fix |
| --- | --- | --- |
| Onboarding led to account actions that cannot complete | The story routed to presentation-only traveler auth despite guest mode being the implemented path | Finish and Skip now enter guest mode and clear the stack to Home |
| Legacy login could display a blank intermediate frame | The widget redirected from `initState` rather than rendering a useful state | Render an honest guest-entry surface with a direct action |
| Guest upgrade copy/button overflowed at 320 px and 160% text | A rigid horizontal row and fixed-size action assumed normal text | Use width/text-aware vertical composition and flexible native controls |
| Shared auth actions overflowed at large text | Labels lived in fixed-height, non-flexible rows | Use flexible labels and opt into intrinsic height only when scaled text needs it |
| Profile statistics vanished at zero | The row was conditionally removed instead of representing the empty value | Keep the stats row stable and expose keyed semantic values |
| Heritage POIs could receive the generic landscape fallback | `normalizedCategory == other` short-circuited meaningful raw category/name aliases | Resolve semantic raw aliases before accepting the generic normalized fallback |
| Local fallback image region could be blank for a frame | `Image.asset` had no pre-decode frame treatment | Add a neutral `frameBuilder` placeholder until the first asset frame arrives |
| Account state-card behavior could diverge | Account screens duplicated the shared `YCStateCard` implementation | Remove the local copy and use the shared scaffold component |
| Visual tests failed against obsolete product states | Goldens and selectors reflected older copy/layout and ambiguous text counts | Refresh reviewed baselines and use stable semantic/value keys in tests |

## Performance

- `[IMPLEMENTED]` No new network request, provider call, database read, or blocking
  navigation await was introduced.
- `[IMPLEMENTED]` Place cards remain useful while images decode; local fallbacks
  now paint a lightweight neutral region instead of a blank frame.
- `[IMPLEMENTED]` Consolidating the state card removes duplicate rendering logic
  and keeps loading/empty/error behavior consistent.
- `[IMPLEMENTED]` The existing cache-first Discover pipeline, image cache,
  skeleton geometry, reduced-motion behavior, and map state handling were left
  intact and covered by the regression suite.
- `[UNKNOWN]` Release-profile frame timing and image decode cost on a physical
  low/mid-range Android device were not measured in this pass.

## Components

- Reused the shared `YCStateCard` for account loading, empty, and error states.
- Made `OnboardingPrimaryButton`, `YCGoogleButton`, and `YCGhostButton`
  scale-aware without disabling accessibility text scaling.
- Made the profile guest upgrade strip responsive to width and effective font
  size.
- Strengthened `PlaceImage` local fallback rendering and image semantics.
- Added stable profile statistic keys for accessible, non-copy-dependent tests.

No external UI or animation dependency was added.

## Protected screens

- `[IMPLEMENTED]` Home was not visually redesigned. Its source files and approved
  composition were not changed; its visual and interaction tests pass.
- `[IMPLEMENTED]` Explore was not visually redesigned. Its source files and
  approved composition were not changed; its 393 px golden passes.
- `[IMPLEMENTED]` The existing onboarding map animation was preserved. Its local
  assets, route painter, progressive behavior, reduced-motion completion, aspect
  ratio, and size-specific goldens pass.

## Testing

Final repository evidence:

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter compact`: **285 tests passed**.
- `flutter build apk --debug --no-pub`: **built**
  `build/app/outputs/flutter-apk/app-regular-debug.apk`.
- Responsive widget coverage includes 320 px narrow layouts, 160% text scaling,
  landscape, average, tall, and large Android-equivalent dimensions.
- New auth coverage exercises Account Entry, Sign In, Sign Up, and legacy Guest
  Entry at 320 x 640 with 160% text scaling and scrolling.
- Place fallback coverage verifies that Hawa Mahal/raw heritage data wins over a
  generic normalized category.
- Home, Explore, four onboarding moments, three onboarding map sizes, destination,
  itinerary, POI, profile, saved, history, and settings goldens were inspected.
- A Pixel 10 AVD was available and launched, but ADB reported it offline, so a live
  emulator interaction recording could not be completed. The debug APK, dimension
  matrix, interaction tests, and goldens are the mobile-equivalent evidence for
  this pass.

The Android build emits a forward-looking Flutter warning that Kotlin 2.2.20 will
eventually need upgrading to at least 2.3.20 and migration to built-in Kotlin. It
does not fail the current build and was not changed as part of this UI scope.

## Remaining issues

- `[PARTIAL]` Traveler sign-in, registration, ownership binding, durable profile/
  trip history, and notification delivery require the planned backend/product
  work. Account surfaces label that limitation and onboarding does not pretend it
  is available.
- `[UNKNOWN]` Physical-device accessibility, TalkBack reading order, keyboard/IME
  behavior, offline map tiles, and release-profile 60 fps should be validated on
  representative Android hardware.
- `[UNKNOWN]` Live provider failure and stale-cache timing depend on a configured
  backend environment; deterministic loading/error/cache UI paths are covered by
  tests, but this pass did not perform external provider writes or production
  migration work.
- `[PLANNED]` Address the Flutter Kotlin migration warning in a dedicated Android
  toolchain change, with its own build verification.
