# Offline starting location correction

Date: 2026-10-04

## Behavior

`[IMPLEMENTED]` Trip setup now leads with “Where will you start in Jaipur?” and accepts a
bundled place, hotel, GPS position or a directly chosen coordinate. Train, Flight, Bus, Car and
Other are optional and can be cleared. Changing travel method preserves the selected origin.
Full-width starting options replace the asymmetric fixed-width transport cards.

`[IMPLEMENTED]` The map picker places bundled landmarks on a coordinate view and accepts any
tapped point, typed coordinates or an explicitly selected city centre. It makes no tile or
geocoder request. Coordinates must be finite and within latitude/longitude bounds. Its UI
explains that offline roads and map imagery are absent.

## Proven causes

1. The local location adapter omitted `country_code` and `result_type`, which the typed model
   requires. A valid matching record consequently raised “Location suggestions were invalid.”
2. Android emulator SQLite reported `no such module: fts5` when a search accessed the packaged
   virtual table. Desktop SQLite had the module, so earlier desktop tests missed this failure.
   Searches now fall back to parameterized name, normalized-name and alias matching on ordinary
   columns. Hotel/category filters, limits and ordering apply on both paths. Unsupported FTS is
   remembered for the open repository instead of repeatedly raising the same database error.
3. The screen required a separate arrival name even for GPS or hotel starts, and silently
   appended transport terms to a user's search. Both restrictions have been removed.
4. Local formatted addresses sometimes contained only a street. They now retain the selected
   place name, so the saved starting location identifies the place the user selected.

## Verification

- `[IMPLEMENTED]` Full Flutter suite: **302 passed**. Static analysis: **no issues**.
- `[IMPLEMENTED]` Real SQLite regression with an unavailable FTS5 module verifies station-name,
  alias and hotel search, safe handling of punctuation and empty results.
- `[IMPLEMENTED]` The typed-service and widget integration selects the actual Mansarovar metro
  station and creates/persists the trip with **zero network requests**.
- `[IMPLEMENTED]` Tests cover GPS and hotel starts without a separate arrival point, invalid
  coordinate rejection, an unlisted coordinate, permission denial, and selecting/clearing Train
  without invalidating the origin.
- `[IMPLEMENTED]` Planning layouts render at 393 logical pixels and at 320 pixels with 1.6 text
  scaling. Updated goldens cover the new starting screen and optional-mode trip summary.
- `[IMPLEMENTED]` The regular release APK on an Android emulator in airplane mode finds
  Mansarovar metro station, accepts the result and advances to step 4 without a travel method.
  Returning to step 3, selecting an unlisted point at 26.96799, 75.76536 and completing steps
  4 and 5 creates the trip and opens Discover with local recommendations, still offline.
  See [confirmed starting point](verification/offline-start-confirmed.png) and
  [created offline trip](verification/offline-trip-created.png).
- `[PARTIAL]` Physical-phone acceptance and measured motion/performance are not established by
  desktop tests or emulator screenshots.

Logs are in `scratch/city-loop/start-fix-full-tests.log`, `start-fix-analyze.log`,
`android-fts-fix-tests.log` and `start-fix-build.log`.

## Initial verified APK (superseded)

`[IMPLEMENTED]` The regular release APK is `build/app/outputs/flutter-apk/app-regular-release.apk`.
The rebuilt APK is **105,443,361 bytes**. SHA-256:
`2ae17dac161f24ddf1f05d9b69cf214e45eb68c97d28dda4c4e8decea5e27057`.
All 37 checksummed pack files match the manifest. Structured inventory is in
[city-pack-artifacts.json](verification/city-pack-artifacts.json).

The initial APK used pack `v4-citylab-offline-01`: 684 places, including 214 hotel-category records,
two named metro stations and Jaipur International Airport. Jaipur's main railway station is
not present in this pack. Direct point selection makes that coverage gap non-blocking.

This remains a testing release with the pack's existing media provenance and test-only media
designation. Offline street tiles, road routing and live weather are outside this correction.

`[IMPLEMENTED]` A subsequent correction adds Jaipur Junction, contextual suggestions and offline route
connections. Its new APK supersedes the hash above. See [the current report](OFFLINE_ROUTE_SEARCH_FIX.md).
