# Home material refinement — 2026-09-09

## Scope and direction

`[IMPLEMENTED]` Focused Flutter material/interaction changes, not a Home redesign.
The approved Figma frame `xgUd2FZFUscBxVEvMOT97N / 18:16` was inspected read-only.
No Figma writes, new images, dependencies, backend/model/route changes, provider
calls, global theme changes, or commits. Existing uncommitted work is preserved,
including the unrelated `docs/PROJECT_STATUS_AUDIT.md`.

The UI-design and Figma design-to-code workflows kept the existing hierarchy,
oversized Inter headings, blue/yellow background, original imagery and vectors,
and Create Trip button proportions. The differentiator is shallow edge lensing
on selected controls, not a new screen-wide glass treatment. No external component
inspiration was used. The configured Wanderlog reference directory is absent in
this checkout; the user's screenshot and approved Figma context were available.

## Exact root cause and interaction fix

Before this refinement, `HomeAction` in `home_style.dart` wrapped every custom
action in `Tooltip -> Material(type: transparency) -> InkWell`, with
`borderRadius: BorderRadius.circular(99)` and no hover, focus, highlight, overlay,
or splash overrides. Navigation stretched five such wrappers across a Row over
the independently painted glyphs. The InkWell's default Material state layers
therefore occupied the large nav hit slots, not just the small SVG icons. This
produced the grey/translucent hover and press circles. The Tooltip's `message`
produced the separate visible "Discover" popup. These were not destination
image artifacts or an IconButton/ButtonStyle problem.

`[IMPLEMENTED]` Only Home's shared `HomeAction` was changed. There is now no
Material/InkWell/InkResponse/Tooltip in this wrapper: `GestureDetector` handles
tap/down/up/cancel, `AnimatedScale` changes 1 -> .97 -> 1 over 130 ms using
easeOutCubic, and reduced-motion settings remove the animation. Card images and
nav glyphs are inside the press transform, not beneath an empty overlay.
`Semantics` retains a labelled button/tap action and selected/toggled state.
`FocusableActionDetector` preserves keyboard activation and a thin keyboard-only
focus outline. Pointer hover adds no state fill. Nav labels are Home, Discover,
Create Trip, Saved and Profile. No application-wide Material theme was changed.

## Reusable optical material

`[IMPLEMENTED]` `YatraRefractiveGlass` owns all renderer selection and loading.
Its `.frag` shader samples the actual backdrop supplied by `ImageFilter.shader`,
not a copied background image or manually captured screenshot. A rounded-rectangle
signed-distance field supplies edge distance and surface normals. A narrow band
(at most 12 logical px) bends sampling inward by roughly 1–3.8 logical px, with
slightly stronger corners. Center magnification is only 0.15%. There is no time
uniform, oscillation, chromatic aberration, or continuously ticking animation.

The shader integrates a normalized nine-tap softening kernel (1–2.2 logical px
sampling offsets at current call sites). This supplies restrained backdrop blur
without a second filter pass inflating the shader's texture bounds. Translucent
fill and a top-left highlight/bottom-right darkening gradient are separate paint
layers so fill/tint is not lost underneath a gradient shader. A subpixel light
border and inner optical rim finish the material. Only the navigation capsule
has a restrained 5%-opacity, 8 px blur, 2 px offset outer shadow.

Program loading is cached as one Future for the process. Each mounted surface
owns one shader/filter pair and disposes its shader; mutable uniforms are not
shared between different sizes. Engine-owned floats 0/1 and sampler 0 are never
set by the widget. Logical dimensions, radius, displacement, and softening occupy
floats 2–6. GLES input sampling explicitly flips the texture y-coordinate.
Every filter is clipped to its local rounded bounds; no fullscreen filter is
added for a small control. The pre-existing background painting remains unchanged.

Applied to search, Continue, Create Trip, destination hearts, the floating nav
capsule and selected Home control. The Planning chip stays white for its existing
status contrast; the hero and destination cards stay image-first. Where Next's
large illustration panel is unchanged. Create Trip keeps its original width,
height, type, amber border and hierarchy, with no white optical rim overriding
that border; it only receives shallow backdrop lensing/softening and press motion.

### Platform behavior

- Android with runtime `ImageFilter.isShaderFilterSupported == true` (Impeller):
  actual backdrop refraction plus the shared fill/rim treatment.
- Unsupported Android rendering, Skia, or shader load/initialization failure:
  clipped `BackdropFilter` Gaussian blur plus translucent fill/gradient and rim.
- Web: deliberately uses that fallback and never initializes a backdrop shader.
  Web fallback is not claimed to be real refraction.
- High contrast: stronger fill and no lens distortion. Bounded constraints are
  required for refraction; unbounded use degrades to blur.

API contracts verified against installed Flutter **3.47.0 / Dart 3.13.0** and
official documentation on **2026-09-09**:
[ImageFilter.shader](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html),
[fragment shader guide](https://docs.flutter.dev/ui/design/graphics/fragment-shaders).
The capability guard is important: a platform-name check alone does not establish
Impeller support.

## Favorites and responsive layout

`[IMPLEMENTED]` `YatraFavoriteButton` has a 48 x 48 logical-pixel touch target,
44–48 px visible glass circle, approximately 24–26 px wide original heart SVG,
and 10–14 px top/right insets driven by card width. Both states retain the same
circle. Selected uses the original warm red filled SVG and a tiny warm glass tint;
unselected uses the original white outline. The heart crossfades over 140 ms with
the shared press-scale motion. The favorite action is a sibling of the card action,
so toggling a heart does not navigate into trip creation.

`[PARTIAL]` These are explicitly session-only Home toggles, initialized from the
illustrative design (Jaipur selected). They are not persisted account favorites.
Search, Discover, destination cards and both Create entries still use the existing
trip-creation entry; Continue, Saved and Profile retain their prior availability
notifications. No account/TripDraft/backend semantics were invented.

LayoutBuilder drives actual viewport width, capped at 700 logical px on wide
screens. Page padding is a width-derived fraction clamped to 20–40 px. Actual
remaining width constrains both large cards; two Expanded destination cards share
that width with a proportional gap. Reference ratios scale individual visual
details, not a transformed full-screen frame. The only FittedBox for the entire
reference canvas is the existing decorative background, not interactive content.
The floating capsule clamps to 280–500 px wide and 64–99 px high, leaving all five
slots at least 48 logical px. SafeArea protects header/navigation. Bottom scroll
padding leaves every card accessible above the floating capsule.

Large headings retain their existing type direction. TextPainter measures the
hero title and destination captions at the active text scale. Cards grow rather
than shrinking text; destination captions reserve clearance below the larger
hearts. The approved source spellings remain unchanged.

## Validation

- `flutter analyze`: no issues found.
- Original 23 relevant tests retained (tooltip finders adapted to accessible custom
  actions). Added hover/press/cancel/keyboard, all-five-nav taps/semantics, fallback
  clip, favorite-toggle and target phone-width tests.
- Compiled shader tests use actual rendered pixel samples at DPR 1 and 3 to check
  inward edge displacement, unchanged center and opaque output. They use the Canvas
  shader path in the test renderer, **not** an Impeller backdrop integration test.
- All **33** tests across the seven suites below pass. Golden files were rerendered
  and visually inspected; they depict the fallback, not Android refraction.

```text
flutter test test/home_screen_test.dart test/yatra_glass_shader_test.dart test/home_web_smoke_test.dart test/widget_test.dart test/route_coverage_test.dart test/trip_creation_test.dart test/flow_updates_test.dart
flutter build apk --debug --flavor regular
flutter build web --no-web-resources-cdn
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8123
```

Final Android debug rebuild passed (17.3 seconds), producing
`build/app/outputs/flutter-apk/app-regular-debug.apk`. Read-only APK archive inspection
confirmed `assets/flutter_assets/shaders/yatra_refractive_glass.frag` is bundled.
Self-contained web build passed (including the compiler's Wasm dry run). The app
was started on port 8123 and the server returned HTTP 200. Windows denied the
first attempted port 55551; no existing local development server was stopped.
The Chrome JavaScript and Wasm test harnesses stalled before emitting test results.
A minimal Chrome probe with no Home imports also stalled during loading. Browser
runtime validation is therefore **unverified**, not a pass; its underlying cause
is not established. The cross-platform smoke test passes in the normal Flutter
test renderer, which does not prove browser behavior. Interactive Browser connection
discovery returned no available browser. The task-owned probe files were removed
and diagnostic processes stopped after checking; the user's prior localhost server
was left untouched. The temporary port-8123 server was also stopped.

The 360/393/412/430 px phone renders check equal-width destination cards, non-overlap
of hero text/date, favorite states, navigation taps and safe-area positioning.
Existing 320/600/short-landscape checks exercise 2x system text and assert that
destination captions remain below both larger hearts. Widget scrolling
and navigation pass; this is not a device frame-time or jank benchmark.

No physical Android device was connected. Still inspect on real Impeller/Vulkan
and GLES devices: live backdrop alignment when scrolling, lens strength at device
DPR, nested selected-nav filtering, press/cancel transitions, system bars, GPU
frame times and lower-end scrolling performance. Build success and mathematical
shader tests do not prove those physical-renderer characteristics. Existing
Kotlin/Gradle deprecation and web Cupertino-font warnings are outside this slice.

## Files changed in this refinement

- `lib/screens/home/home_screen.dart`: local toggles and viewport padding constraints.
- `lib/screens/home/widgets/home_style.dart`: shared interaction/semantics.
- `lib/screens/home/widgets/yatra_refractive_glass.dart`: reusable material.
- `lib/screens/home/widgets/yatra_favorite_button.dart`: larger controlled hearts.
- `lib/screens/home/widgets/home_bottom_navigation.dart`: glass capsule and YatraNavItem.
- `lib/screens/home/widgets/home_destination_card.dart`: heart placement, caption clearance, card press.
- `lib/screens/home/widgets/home_search_bar.dart`: shared material.
- `lib/screens/home/widgets/continue_planning_card.dart`: Continue material.
- `lib/screens/home/widgets/where_next_card.dart`: Create material, preserved amber outline.
- `shaders/yatra_refractive_glass.frag` and `pubspec.yaml`: registered native shader; no new package.
- `test/home_screen_test.dart`, `test/widget_test.dart`, `test/yatra_glass_shader_test.dart`,
  `test/home_web_smoke_test.dart`.
- `test/goldens/home_700x1463.png`, `home_390x844.png`, and
  `home_refined_360.png`, `home_refined_393.png`, `home_refined_412.png`, `home_refined_430.png`.
- `docs/ARCHITECTURE.md`, `docs/HOME_FIGMA_IMPLEMENTATION.md`, and this report.

The image/font/SVG assets, HomeHeader and HomeBackground are unchanged by this
refinement. Git's total diff also includes the user's uncommitted preceding Home
implementation; it should not be mistaken for a rewrite performed in this pass.
