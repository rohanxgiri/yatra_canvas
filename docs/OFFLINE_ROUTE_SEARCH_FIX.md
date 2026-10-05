# Offline route, start search and imagery correction

Verified 2026-10-04. This report supersedes the APK inventory in
[the earlier starting-point report](OFFLINE_START_LOCATION_FIX.md).

## Outcome

`[IMPLEMENTED]` The prepared Jaipur flow searches and selects starting points without a backend.
Hotel selection immediately browses lodging. Optional Train selection browses railway/metro stations;
Flight selection browses airports. The airport is excluded from station suggestions. Changing an
optional method preserves a confirmed starting point. Selecting a method for an unconfirmed start
brings the updated suggestions into view. No arrival method is required to continue.

`[IMPLEMENTED]` The new immutable pack `v5-offline-startpoints-01` has **685 places**, including
Jaipur Junction railway station and aliases such as Jaipur railway station. The name and coordinate
26.920203, 75.786923 were checked against [Wikidata Q6124154](https://www.wikidata.org/wiki/Q6124154),
revision 2529252551, on 2026-10-04. Structured-data CC0 licensing was checked against
[Wikidata licensing](https://www.wikidata.org/wiki/Wikidata:Licensing) on the same date.
The source-backed ADD passed the existing DataFactory dry-run review, then created a new release
and validated Flutter projection. The previous release fingerprint is unchanged. Opening hours and
photos for this station remain unknown. See [source audit](verification/jaipur-start-station-source.json)
and [reviewable patch](verification/jaipur-start-station-patch.zip).

`[IMPLEMENTED]` Local planning schedules stops and produces an offline route overview. Each populated
day connects the selected origin to non-skipped stops in visit order. The itinerary and route-geometry
reads derive this overview from persisted data, so older local trips also gain route lines. A map with
saved places and no itinerary offers **Plan route offline**. The explicit action saves the itinerary
and updates its parent screen. Opening the map itself does not optimize or overwrite an itinerary.

`[IMPLEMENTED]` Exact bundled photos take priority. Canonical pack places without an exact photograph
use identifiable, non-photographic placeholders with stable color variation and a missing-photo label
when space permits. This replaces repeated category photographs on those cards without pretending an
unrelated image depicts a particular hotel or attraction. The pack still has **18 real place photos**;
this correction does not manufacture additional photos.

## Proven causes and limits

- `[IMPLEMENTED]` Android SQLite builds without FTS5 could not execute the pack's virtual search table.
  The existing ordinary-column fallback now also honors contextual location filters and canonical
  aliases. Selected-city qualifiers do not prevent matching a local place.
- `[IMPLEMENTED]` The prior offline route-geometry handler always returned an empty day list, so the
  map could display pins but no route lines. It now returns ordered coordinate connections.
- `[IMPLEMENTED]` The previous map depended on internet tiles. Local-trip maps now avoid those requests
  and clearly explain the coordinate overview, with a separate panel that cannot cover map controls.
- `[IMPLEMENTED]` The original pack lacked Jaipur Junction, and the same small category-photo library
  filled most missing photo slots. The new station record and placeholder treatment address these
  two separate data/presentation gaps.
- `[PARTIAL]` Offline lines are **straight coordinate connections**, with approximate local travel
  estimates. Street-map tiles, road-following geometry, turn-by-turn navigation, live weather and
  backend solver parity remain unavailable offline. This is an itinerary overview, not road navigation.

## Verification

- `[IMPLEMENTED]` **307 Flutter tests passed**; static analysis reported **no issues**.
- `[IMPLEMENTED]` **14 DataFactory patch/export tests passed**. Both the reviewed source release and
  the new app pack are validated; old-release fingerprints and packaged asset hashes are checked.
- `[IMPLEMENTED]` Real-pack integration exercises automatic Hotel, Train and Flight suggestions,
  then selects Jaipur Junction and creates/persists its trip with **zero network requests**.
- `[IMPLEMENTED]` Local route integration confirms each day starts at the custom origin, follows
  scheduled stop order, survives restart and works when network access is unavailable.
- `[IMPLEMENTED]` Map/point-picker widgets render at 393 pixels and 320 pixels with 1.6 text scaling.
  The offline map contains route polylines and no internet TileLayer. Explicit map planning is tested.
  The arbitrary-point picker accepts an unlisted coordinate without covering landmarks in text.
- `[IMPLEMENTED]` Missing-photo cards use a labelled placeholder; existing exact-photo and online
  image behavior remains covered by the image suite.
- `[PARTIAL]` Android airplane-mode proof for the earlier starting-point fix is recorded in the
  previous report. The latest route/context/station changes have widget, SQLite and APK evidence;
  the rebuilt APK has not been accepted on the physical phone. The emulator became unavailable
  during the earlier final recheck. Measured frame performance is not established.

Rendered evidence: [Jaipur Junction selected](verification/offline-start-location-v2.png),
[route overview](verification/offline-route-overview.png),
[offline point picker](verification/offline-point-picker.png).
Logs: `scratch/city-loop/offline-route-full-tests.log`, `offline-route-analyze.log`,
`station-factory-tests.log`, `station-import.log`, `station-sync.log`, `offline-route-build.log`.

## Current APK

`[IMPLEMENTED]` Use **`build/app/outputs/flutter-apk/app-regular-release.apk`**. This is the single
rebuilt regular APK; earlier APK copies are superseded. Its byte size, SHA-256 and complete pack
inventory are recorded in [city-pack-artifacts.json](verification/city-pack-artifacts.json).
The existing test-release/media classification is retained. No backend migrations, production
deployment, paid AI calls or changes to physical-phone settings were performed.

`[IMPLEMENTED]` Final artifact: **105,460,081 bytes**, SHA-256
`64909c70f46177c5a729e39cae945c88b354a2596d5caa03ef816f2456c38562`. All **37** checksummed pack assets match the bundled manifest.
