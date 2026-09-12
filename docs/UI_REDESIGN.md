# YatraCanvas UI redesign

Reviewed 2026-09-13. This is a staged client redesign, not a backend or identity migration.

## Reference and protected scope

The approved Figma file `xgUd2FZFUscBxVEvMOT97N` was inspected read-only: Home `18:16`, Explore `30:54`, and their design context and screenshots. Their layouts, bundled imagery, typography, glass widgets, navigation styling, and golden references remain protected. The requested Wanderlog reference directory was absent from this checkout; no substitute visual language was introduced.

## Shared foundations

`[IMPLEMENTED]` `YCStyle`, `YCCanvas`, and `YCScaffold` scope the planning/account theme locally. Home and Explore retain their own components and theme. Shared legacy typography and accent aliases now agree with these foundations.

| Foundation | Implementation |
| --- | --- |
| Typeface | Bundled HomeInter; light page headings and medium section/control labels |
| Type scale | Display 34, page 32, section 20, body 16, secondary 14, caption 12; labels wrap rather than shrink |
| Color | Navy `#141B34`, travel blue `#055EC8`, muted `#526077`, selection `#E7F0FF` |
| Canvas | Cream through pale blue for extended planning sessions; stronger approved blue composition on onboarding |
| Spacing | 4, 8, 12, 16, 24 screen gutters, 32 section spacing |
| Surfaces | White cards with thin borders, nominal 18 radius; modal/bottom-sheet radius 28 |
| Controls | Capsule primary/secondary buttons, minimum 52 height; selection chips and icon actions minimum 48 |
| Interaction | Local no-ripple theme; explicit pressed, focus, disabled, and loading states; native semantics |
| Glass | Existing approved glass remains on Home/Explore; working forms use solid readable surfaces |
| Motion | Short transitions; onboarding navigation and launch respect reduced-motion preferences |

Reusable building blocks include existing `PrimaryButton`, `SelectionChip`, `SearchField`, `ProgressHeader`, `HomeDestinationCard`, `YatraBrand`, and the new `YCStateCard`. `PlaceCard` now supports clear selection, useful metadata, optional imagery, and separate details/add actions without a large empty image placeholder.

## Screen audit and implementation decisions

Each row records the problem, intended task, structure, visual inheritance, and component choice used before or during its staged review.

| Screen | Problem and UX objective | Structure and component decisions |
| --- | --- | --- |
| Splash | Older launch was disconnected from onboarding; introduce the journey without artificial progress | Small brand, restrained travel copy, brief fade into the story; reuse brand and canvas |
| Onboarding | Repeated marketing/questionnaire steps delayed planning | Three stories: discover, plan, adapt; one coherent custom artwork, native itinerary/interests previews, shared footer and progress |
| Legacy welcome/login/personalisation | Separate older layouts and unimplemented sign-in actions | Welcome and personalisation route to the same three-page story; login becomes an honest guest entry; trip preferences belong in the trip |
| Destination | Blank entry offered little guidance and exposed database-origin labels | Search first, recent session destinations or two inspiration queries, city/state results, selected-city summary; preserve debounce, resolve, retry and empty states |
| Dates | Default-feeling calendar details and cramped month navigation | Custom range calendar, first/last-day hint, summary, flexible duration, safe footer; correct flexible end-date synchronization |
| Arrival | Large transport tiles competed with actual location selection | Compact transport chips, coordinate-backed arrival search, time, then conditional starting-point choices; preserve permission and resolution behavior |
| Interests/purpose | Large repetitive cards and overlapping preference questions | Compact multi-select rows with visible checks; preserve the existing purpose payload; no additional redundant purpose questionnaire |
| Preferences | Fixed dates in summary, compressed labels, too much competing information | Pace, budget, transport, collapsed trip summary; preserve create/update busy and error handling |
| Recommendations | Raw ranking values and oversized placeholders made results feel like API records | Curated name/category/reason/available metadata, category filtering, native details, separate add/remove actions; preserve deduplication and reconciliation |
| Processing | Spinner-only route feedback gave little context | Descriptive state tied to the real pending request; no fabricated percentages or unsupported provider stages |
| Selected places | Inline controls squeezed names and schedule targets on narrow screens | Place name/schedule first, controls on their own row; keep reorder, notes, locking and removal; persistent review action |
| Itinerary/day details | Dense repeated labels and all days competing for attention | Expandable day sections, ordered stops, travel transitions, opening-hour notes, secondary action menu; wrapping time/day labels |
| Rest days | Empty-looking schedule failed to communicate intention | Explicit rest-day label and calm explanation; day settings preserve intentional no-sightseeing constraints |
| Day settings | Repeated heading, unrelated badge colors, cramped day/type row | One introduction, compact selectable day cards, wrapping labels, locally themed editing sheet; preserve saving/validation |
| Map | Controls and loading treatment did not match planning | Quiet overlays, day filter, fit/zoom actions, route and POI layers retained; map content remains functional |
| POI sheet | Competing metadata and default modal/control styles | Category and stop context, place name, schedule/duration/hours, visit status, directions and details; wrapping labels and consistent sheet surface |
| Missed-stop changes | Many possible changes could overwhelm the itinerary | Keep changes in the existing contextual menu/sheet; preserve backend feasibility feedback and rest-day exclusions |
| Trip summary | No concise return-to-trip view | Destination/dates, collapsed context, continue/map actions, day settings and saved places; independent section requests retain partial results |
| Saved | Placeholder access and no dedicated destination collection | Reuse HomeDestinationCard and the caller's favorite set; open genuine destination search; link trip-specific saved places through history |
| Profile | Placeholder access; no real authentication | Guest identity, saved destinations, session trips, preferences/settings; explicit session scope |
| History | No authenticated trip-list endpoint | Remember successful trip creations/updates in the current session; upcoming/ongoing/past derived from dates, not fabricated completion status |
| Settings | No coherent traveler settings surface | Session name/default pace, real device location-settings action, truthful appearance/notification availability, clear recent-session list |

## State and data boundaries

`[IMPLEMENTED]` `YatraSession` remembers snapshots of successful trip saves and session preferences. Draft edits do not silently mutate previously remembered trips. It creates no fake trip IDs and does not change server ownership.

`[PARTIAL]` Saved/Profile screen implementations are not connected to protected Home/Explore handlers pending explicit resolution of the navigation constraint. Favorite data remains caller-owned. Account authentication, account synchronization, durable local history, notification delivery, and a backend trip-list endpoint are not implemented by this redesign.

`[IMPLEMENTED]` Existing services remain responsible for city search/resolution, coordinate-backed starting points, trip saving, recommendations, saved-place CRUD, route optimization, status changes, replanning, and route geometry. No provider, environment, endpoint, schema, migration, or deployment change is included.

Loading/error/empty states are tied to actual request state. Existing recommendations and saved places survive supported refresh failures; summary requests preserve independently loaded sections. Unknown hours remain unknown. Session-only screens say so. Physical-device offline recovery, accessibility services, real map tiles, and live-provider behavior still require device acceptance testing.

## Verification

The Flutter suite covers service boundaries, duplicate prevention, save reconciliation, day restrictions, status changes, replanning, maps and POI actions. Added checks cover the three-page onboarding route, mobile layouts, flexible-date consistency, session snapshots, and partial summary failure/retry.

Visual baselines under `test/goldens/` cover onboarding, five planning steps, account screens, day settings, populated itinerary and POI details. Layout checks include 393-pixel phones and 320-pixel phones at 1.6 text scale; onboarding also covers landscape and 430-pixel devices. Image assets are decoded before account snapshots. Home/Explore goldens are not regenerated.

This document does not declare the entire product production-ready. Navigation integration and physical-device acceptance remain explicit follow-up gates.

Latest verification on 2026-09-13: complete Flutter suite passed 207 tests. After
the final profile-count and initial-history-category fixes, all five account tests
passed, including two new interaction checks. Final `flutter analyze --no-pub`
reported no issues. `flutter build apk --debug --no-pub` produced
`build/app/outputs/flutter-apk/app-regular-debug.apk`. The Android build was not
installed on a physical device. `git diff --check` passed; comparison against
pre-redesign checkpoint `222225e` confirmed no changes to Home/Explore source,
their shared navigation widget, or their golden images.
