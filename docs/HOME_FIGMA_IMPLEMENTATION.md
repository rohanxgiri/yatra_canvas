# Original Figma home implementation

Historical baseline report. The subsequent user-requested material/interaction
refinement is documented in [HOME_MATERIAL_REFINEMENT.md](HOME_MATERIAL_REFINEMENT.md).
That refinement supersedes the original tooltip, favorite, navigation minimum-size,
glass-approximation, and validation notes below. The two named golden paths now
contain the refined UI; the Figma measurements remain reference measurements.

Source inspected read-only on 2026-09-09:
[approved frame 18:16](https://www.figma.com/design/xgUd2FZFUscBxVEvMOT97N/Untitled?node-id=18-16).
No Figma frames, layers, components, or files were created or modified.

## Mapping and measurements

| Figma element | Flutter widget | Source measurements |
| --- | --- | --- |
| Frame | HomeScreen | 700 x 1463; 40 px side margins |
| Welcome / Mekur | HomeHeader | 64 px Inter, weights 200 / 500; avatar 110 x 112 |
| Search | HomeSearchBar | 620 x 62; y=217; radius 12 |
| Continue planning | ContinuePlanningCard | 620 x 341; y=363; radius 18; 64 px title |
| Continue control | HomeAction inside continuation card | 141 x 50; radius 25 |
| Where next? | WhereNextCard | 620 x 252; y=734; 38 px heading; original route vectors |
| Create Trip control | HomeAction inside creation card | 131 x 48; radius 74 |
| Destinations | HomeDestinationCard | two 300 x 234 cards; 20 px gap; y=1056; radius 18 |
| Floating navigation | HomeBottomNavigation | 500 x 99; y=1328; radius 73; Home circle 91 x 91 |

`[IMPLEMENTED]` Normal layout uses a sliver column with scaled gaps and two Expanded
destination cards. Local card artwork uses measured relative positions and a scale
computed from LayoutBuilder width. The navigation is bottom-anchored inside SafeArea;
shorter screens scroll. Text expansion increases card heights, and small controls have
larger invisible hit regions where space permits. The home font is scoped locally.

The shared Material TripCard, DestinationCard, SectionHeader, and AppBottomNavigation
were inspected, but their separate image/body layouts, typography, and standard
NavigationBar conflict with the approved composition. They remain available to existing
callers. The home uses custom presentation widgets, the existing Navigator route,
existing DestinationSelectionScreen, and the already-installed flutter_svg renderer.

The only intentional copy change from Figma is the search prompt:
“Where do you want to go?” The source spellings “Spritual Trip” and “Rajisthan” are
preserved along with the supplied username and dates.

## Assets and functionality

Exact downloaded assets and origin nodes are recorded in
[asset sources](../lib/assets/home/SOURCES.md).
No runtime Figma URL or font request is needed.

`[IMPLEMENTED]` Both Create controls open the existing trip setup flow. Search,
Discover, and the destination tiles use the same existing destination-search entry.
Home returns the scroll position to the top. No service, model, backend, provider,
API, cache, migration, or persistent trip state was changed.

`[PARTIAL]` Continue still shows the original “Trip planning is coming in the next
phase” notification: the previous home had no saved-trip selection. Profile and
Favorites likewise have no corresponding application screens or persistence here.
The home does not claim to have loaded a real account or resumed a fabricated trip.

## Visual verification and remaining differences

The actual HomeScreen was rendered with Flutter and the bundled font at 700 x 1463
and 390 x 844 (24 px simulated top/bottom system insets). The frame render was compared
visually against Figma, then saved as a golden baseline:

- [700 x 1463 render](../test/goldens/home_700x1463.png)
- [390 x 844 render](../test/goldens/home_390x844.png)

The original image crop, font sizes/weights, major positions, card dimensions, route,
navigation glyphs, progress proportion, and background direction are reproduced.
Golden tests protect the reviewed Flutter output; they are not an assertion that
Flutter and Figma produce identical pixels.

Remaining differences: native blur/gradient compositing and subtle translucent rim
effects vary from Figma. MCP supplies the original fills and source vectors but does
not expose all settings behind the rendered translucent controls. The Continue and
favorite controls use small local blur approximations of those visible source effects.
The Create button retains the exported amber stroke; its Figma render has a slight
violet rim. There is no added screen-wide glass redesign. Font rasterization varies
by platform. Safe areas and shorter aspect ratios intentionally affect the amount
of content visible before scrolling.

## Verification commands

```text
flutter analyze
flutter test test/home_screen_test.dart test/widget_test.dart test/route_coverage_test.dart test/trip_creation_test.dart test/flow_updates_test.dart
flutter build apk --debug --flavor regular
```

Final analyzer result: no issues found. All 23 tests in the five listed suites pass,
including golden comparisons, 320/390/600 px widths, a short landscape viewport,
2x text, safe-area positioning, and the existing trip-creation/navigation flows.
The new test checks that enlarged trip titles remain above the date row.
`git diff --check` passes.

Final Android debug build: passed (43 seconds), producing
`build/app/outputs/flutter-apk/app-regular-debug.apk`.
No physical Android device was connected for runtime testing; visual comparisons
use the Flutter test renderer. Existing Kotlin/Gradle deprecation warnings are
outside this UI change.

## Files changed

- `lib/screens/home/home_screen.dart`: screen composition and existing callbacks.
- `lib/screens/home/widgets/home_header.dart`
- `lib/screens/home/widgets/home_search_bar.dart`
- `lib/screens/home/widgets/continue_planning_card.dart`
- `lib/screens/home/widgets/where_next_card.dart`
- `lib/screens/home/widgets/home_destination_card.dart`
- `lib/screens/home/widgets/home_bottom_navigation.dart`
- `lib/screens/home/widgets/home_background.dart`
- `lib/screens/home/widgets/home_style.dart`: scoped typography, SVG wrapper, and hit targets.
- `lib/assets/home/`: original image/vector assets and `SOURCES.md` inventory.
- `lib/assets/fonts/Inter.ttf` and `lib/assets/fonts/OFL.txt`.
- `pubspec.yaml`: local assets and home-only font registration; no new dependency.
- `test/home_screen_test.dart`, `test/widget_test.dart`, and the two `test/goldens/home_*.png` files.
- `docs/ARCHITECTURE.md` and this implementation report.

The unrelated pre-existing `docs/PROJECT_STATUS_AUDIT.md` was not edited.
No changes have been committed.
