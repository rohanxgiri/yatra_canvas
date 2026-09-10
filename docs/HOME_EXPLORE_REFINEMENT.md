# Home and Explore refinement — 2026-09-10

## Scope and reference

`[IMPLEMENTED]` This pass preserves the approved Home composition and adds the
approved Explore composition. Figma file `xgUd2FZFUscBxVEvMOT97N`, Home node `18:16`,
Explore node `30:54`, and Explore carousel children `32:232`, `32:233`, and `33:261`
were inspected read-only. No Figma write operation was performed.

The visual direction is calm editorial travel: an open cream-to-travel-blue field,
image-first inspiration cards, and a restrained shared glass navigation capsule. Its
signature interaction is the single glass selection lens that glides between fixed
navigation destinations. Existing YatraCanvas images and icons are reused; no AI or
stock image was added.

## Interaction defect and correction

Before the material refinement, `HomeAction` used
`Tooltip -> Material(type: transparency) -> InkWell`. Default Material hover and pressed
state layers painted across the large row slots surrounding the controls, producing the
grey/black blobs. The Tooltip also produced the separate black Discover popup. The issue
was not caused by an image, shadow, or `IconButton`.

`[IMPLEMENTED]` Shared actions now use semantics, focus handling, and pointer gestures
without `Material`, `InkWell`, `InkResponse`, or visual tooltips. Press feedback is a
130 ms scale to 0.97; keyboard focus remains visible and pointer hover adds no fill.

## Shared navigation and glass

`[IMPLEMENTED]` `lib/widgets/yatra_bottom_navigation.dart` owns the five labels, item
semantics, touch targets, shared capsule, and selected indicator. Home and Explore pass
only the current index and destination callback. The indicator is one
`AnimatedPositioned` glass circle using a 280 ms ease-out transition and respecting
reduced-motion preferences.

`[IMPLEMENTED]` Android/Impeller uses the custom backdrop fragment shader with rounded
edge displacement, subtle corner refraction, a very small center lens, integrated
softness, directional rim lighting, and tightly clipped bounds. The fragment program is
cached while each surface owns and disposes its shader. Web, Skia, unsupported devices,
shader-load failures, and high-contrast contexts use the clipped blur/tint/rim fallback.

## Explore composition

`[IMPLEMENTED]` Explore contains the inspiration pill, centered mixed-style heading,
seven-card swipeable carousel, selected-card emphasis, visible neighboring cards,
pagination, and Popular Destinations. Categories are Nature Retreats, Spiritual
Journeys, Food Trails, Mountain Escapes, Hidden Gems, Heritage, and Weekend Escapes.
No invented traveler counts, rankings, or popularity metrics are shown. Popular
Destinations reuses the exact Home destination and favorite components, including the
session-local favorite state shared through the existing Home shell.

## Verification

`[IMPLEMENTED]` Automated checks completed on 2026-09-10:

- `flutter analyze --no-pub`: no issues.
- Full Flutter test suite: 197 tests passed.
- Golden coverage includes Explore at 393 px and Home at supported reference sizes.
- Responsive widget coverage exercises 360, 393, 412, and 430 px widths, scrolling,
  SafeArea placement, carousel side visibility, swiping, semantics, and shared favorites.
- Web smoke coverage navigates Home -> Explore -> Home and verifies the shared navigation,
  fallback backdrop filter, and absence of tooltip/ink response widgets.
- Regular debug APK assembled successfully; the archive contains
  `assets/flutter_assets/shaders/yatra_refractive_glass.frag`.
- Release web output built successfully and was served locally with an HTTP 200 response.

`[PARTIAL]` An Android handset was detected but ADB reported it as unauthorized, so a
physical run was not possible. Shader use, gesture behavior, and packaging are covered by
implementation checks, tests, and APK inspection, but final GPU appearance and sustained
frame timing still require one authorized Impeller device pass. Build-time Kotlin/AGP and
Android SDK XML deprecation warnings are pre-existing toolchain maintenance items; they did
not fail this build.
