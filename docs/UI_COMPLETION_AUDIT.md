# UI completion audit

Reviewed 2026-09-13 against Flutter source, route construction, models, existing
widget/service tests and rendered visual baselines. This pass builds on the existing
[UI redesign](UI_REDESIGN.md); it does not claim the whole application is production-ready.

## References and direction

Read-only Figma MCP inspection included page `0:1`, design context and screenshots
for Home `18:16` and Explore `30:54` in
[the supplied file](https://www.figma.com/design/xgUd2FZFUscBxVEvMOT97N/Cp_Home_Screen?node-id=0-1).
`design_reference/wanderlog/` is absent in this checkout.

The design remains a calm Indian travel journal: light Inter headings, navy text,
cream-to-blue canvases, rounded image-led cards and selective floating glass.
The signature is the illustrated travel story paired with translucent navigation.
Existing YCStyle spacing/type/radius tokens and shared controls are retained.
No external component inspiration or new UI framework was needed; implementation is Flutter.
Artwork is illustrative, as clarified by the user, rather than photorealistic.

## Inventory and decisions

P0 denotes broken/incomplete interaction, P1 misleading states or readability, and
P2 refinement. “Retain” means inspected existing work already supplies that surface;
it does not mean a fresh implementation or physical-device certification.

| Screen/surface | Current state and quality | UX/content/state gap | Decision | Imagery | Priority |
| --- | --- | --- | --- | --- | --- |
| Splash | Branded launch with brief fade | Short viewport and larger text can exceed a fixed column | Scrollable constrained launch content | Brand only | P1 |
| Three-page onboarding | Coherent illustration, native interest/itinerary previews, shared footer | No new screen needed | Retain; existing portrait/landscape tests | Existing custom painted journey | P2 |
| Welcome/personal interests compatibility routes | Delegate to onboarding | Redundant legacy designs already removed | Retain | Same story | P2 |
| Login compatibility route | Honest guest entry | Authentication unavailable | Retain guest scope; no fake login actions | None needed | P1 |
| Home | Approved layout, background, glass and destination cards | Sample identity/trip/favorite/progress; dead Continue/Profile/Saved actions | Connect session state and navigation; keep card hierarchy and composition | Existing city/story assets | P0 |
| Explore | Approved heading, carousel and navigation | Mountain category used palace image; badge constrained enlarged text; city card lost destination | Illustrative mountain category art, wrapping badge, city query handoff | One new painted mountain asset | P1 |
| Destination | Debounced stored/provider search, resolve/retry/empty/selected states | Inspiration list lacked imagery | Add bundled thumbnails only for known illustrated cities; retain genuine search | Existing Jaipur/Varanasi/Ujjain | P2 |
| Dates | Mobile range calendar, flexible duration and date summary | “5+” selected exactly 5 | Label the actual five-day choice; preserve range logic | None | P1 |
| Arrival/start | Method choices, arrival search, hotel/custom/current location, permission errors | No additional step needed | Retain coordinate-backed selection and progressive disclosure | Icons only | P2 |
| Purpose/interests | Expressive icons, full-width selection rows, clear checks | No missing payload or screen identified | Retain existing backend-supported purposes | Icons, no redundant pictures | P2 |
| Preferences | Pace/budget/transport, summary, save/loading/error | No duplicate questionnaire needed | Retain five-step flow and existing save service | None | P2 |
| Generation/recommendation loading | Real pending-state descriptions and indicators | No reliable percent/stage stream exists | Retain truthful indeterminate feedback | None | P1 |
| Discovery/results | Filters, reasons, available metadata, manual search, retry and retained results | Duplicated vertical spacer | Tighten spacing; retain data-driven cards | No fabricated POI imagery | P2 |
| Selected places | Reorder, priorities, locks, notes and day assignment | Existing controls and reconciliation functional | Retain existing implementations and tests | Optional real data only | P2 |
| Itinerary | Expandable days, times, estimates, status and unscheduled reasons | Unscheduled warning could overflow horizontally | Wrap warning text; retain server-generated itinerary | No invented attraction photo | P1 |
| Rest/empty days | Explicit day numbers and intentional rest-day explanation | No missing day screen | Retain | Calm text and icon | P2 |
| Day configuration sheet | Editable day type/time windows, validation/save state | Heading competed with close button | Flexible title and labelled close action | None | P1 |
| Map | Road polylines, numbered markers, POI sheet, fit/zoom/day menu | All Days null selection ineffective; failures silent; empty map at 0,0; attribution no-op | Non-null menu value, visible retry, honest empty state, working attribution | Actual map tiles only | P0 |
| POI details | Schedule, hours, status, move/directions/details | Available rating omitted; launcher exception unhandled | Show rating only if supplied; catch unsupported launches | Model has no place image field | P1 |
| Missed/replanned stops | Contextual actions, feasible-day feedback and authoritative updates | No redesign needed | Retain backend lifecycle semantics and rest-day exclusion | None | P2 |
| Saved destinations | Existing collection and empty screen | Inaccessible from shell; seeded fake favorite | Connect tab and empty-state Explore action; start empty | Same Home destination cards | P0 |
| Profile | Guest identity, saved count, history/settings links | Inaccessible from shell | Connect tab; use session name on Home; dark nav icons on pale canvas | Neutral profile glyph | P0 |
| History/summary | Session snapshots, ongoing/upcoming/past, partial request recovery | Missing entry from Home | Real-ID continuation plus Profile/Saved links | No fake history | P0 |
| Settings | Session name/pace, location settings, about, truthful unsupported features | No meaningful extra settings required | Retain existing scope and behavior | None | P2 |
| Admin | Separate entrypoint; sample operational dashboard | Compact drawer used context above Scaffold; sample data needed identification | Fix context and mark interface preview | No traveller-facing admin link | P0 |
| Shared controls/navigation | Reusable YCScaffold/YCStyle/buttons/chips/brand/glass | Account tab background needs darker glyphs | Extend existing nav with light-surface contrast mode | Existing SVG glyphs | P1 |

## Boundaries

[IMPLEMENTED] Saved/Profile are destinations in the single glass shell. Back from
those tabs returns Home. New-trip actions preserve the selected shell destination.
Successful-save snapshots supply a real trip ID to the continuation surface.
No fabricated progress percentage or seeded personal favorite is shown.

[PARTIAL] Session name, pace, favorite destinations and recent-trip navigation are
not an authenticated account or durable offline store. Server data remains under
the existing ownership model. Authentication, a backend trip-list endpoint,
restart restoration, notification delivery and operational admin APIs are separate work.

[IMPLEMENTED] Existing API contracts, provider configuration, backend services,
database schema and migrations are unchanged. The map remains a read path until
the traveller explicitly performs an existing itinerary action. Unknown hours
remain unavailable, not an inferred open/closed claim. No POI photo/description
fields were invented; supplied ratings are optional.

[UNKNOWN] Physical-device screen-reader behavior, live tile/provider recovery,
offline persistence and production release acceptance have not been established
by widget tests. Previously present glass emulator evidence is preserved in
`docs/visual_checks/`; it is not new evidence for this completion pass.

## Validation

Baseline: the existing complete Flutter suite passed 209 tests before edits.
The added navigation tests cover 320/393/430 px, enlarged text at 320 px, empty Saved,
Profile and Home name updates, real trip ID handoff, destination-query handoff and
the compact admin drawer. Existing map tests now exercise return to All Days and
visible retry after geometry failure. Updated images are decoded before golden
capture. Final analysis, suite and build results follow.

Final results (2026-09-13):

- `flutter test --no-pub --reporter expanded`: **215 passed**.
- Focused visual/planner golden generation: **47 passed**; rendered Home,
  Explore, destination and POI images inspected after capture.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter build apk --debug --no-pub`: **Succeeded**, producing
  `build/app/outputs/flutter-apk/app-regular-debug.apk`.
- `git diff --check`: **Passed**.
- Build emitted an existing Kotlin Gradle Plugin compatibility/deprecation warning;
  this pass does not change the Android toolchain.
- Android APK was compiled, not installed on a physical device during this pass.
  Screen-size and enlarged-text evidence comes from Flutter widget/golden tests.

The pre-existing glass widget edits, related documentation and emulator screenshots
were retained. Generated comparison failures were cleaned up without modifying
the pre-existing failure reference images. No commit or deployment was performed.
