# City-data developer loop

Status: `[IMPLEMENTED]` repository workflow; `[PARTIAL]` physical Android acceptance. 2026-10-04.

The examples use the existing DataFactory virtual environment. Run each command from the named
checkout. All cities are selected by metadata; Jaipur is the acceptance fixture.

## Export and sync

From `YatraCanvas-DataFactory`:

```powershell
.\.venv\Scripts\python.exe -m datafactory app-pack --city Jaipur --dry-run
.\.venv\Scripts\python.exe -m datafactory app-pack --city Jaipur
# Optional explicit immutable source/output:
.\.venv\Scripts\python.exe -m datafactory app-pack --city Jaipur --version v4-citylab-offline-01 --output releases\app_packs\jaipur\custom-output
```

From `YatraCanvas`:

```powershell
..\YatraCanvas-DataFactory\.venv\Scripts\python.exe tools\sync_city_pack.py --city Jaipur --dry-run
..\YatraCanvas-DataFactory\.venv\Scripts\python.exe tools\sync_city_pack.py --city Jaipur
```

For the local test-photo acceptance release, explicitly add `--allow-test-media` to exporter/sync.
Strict and test-media projections have different immutable output directories. Existing fallback
assets are always available, so omitting this flag retains offline usability.

## Human repair

From `YatraCanvas-CityPack-Lab`, configure the DataFactory checkout and its Python interpreter in the
existing Source Settings. Refresh the city baseline using Sync. Find a POI by name, canonical alias,
stable ID or category. Copy the ID from the normal details view or YatraCanvas's debug diagnostics.
Use Edit Details, Edit Aliases, category/coordinate controls, hours editor, or photo curator.
Save persists an overlay; it never edits the canonical release. New places require name, category,
actual coordinates and evidence. Duplicate/identity collisions are reviewed during import.

Photos use Choose photo, source information, license choice and exact-place/real-photo confirmation.
For local unlicensed tests choose `UNVERIFIED_TEST_ONLY`; never treat that choice as reusable media.
Unknown hours stay blank/Unknown; verified schedules require source evidence. Weekly days can be
Closed, Unknown, 24 hours, or intervals such as `11:00-14:00,17:00-22:00`.

Use the release screen's **Export repair patch** action. It creates a reviewable ZIP independently
of strict production certification. The equivalent command from City Lab is:

```powershell
..\YatraCanvas-DataFactory\.venv\Scripts\python.exe tools\export_citylab_patch.py --city jaipur --source ..\YatraCanvas-DataFactory --output artifacts\patches\jaipur-repair.zip
```

From DataFactory, review the printed APPLY/REVIEW/REJECT decisions first:

```powershell
.\.venv\Scripts\python.exe -m datafactory citylab-import --file ..\YatraCanvas-CityPack-Lab\artifacts\patches\jaipur-repair.zip --dry-run --allow-test-media
$repairVersion = 'v-citylab-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
.\.venv\Scripts\python.exe -m datafactory citylab-import --file ..\YatraCanvas-CityPack-Lab\artifacts\patches\jaipur-repair.zip --apply --output-version $repairVersion --allow-test-media
```

Choose a new version for every application. A stale edited field requires re-sync/re-review; unchanged
fields can merge across an older base. Test media needs the explicit flag during import AND export.
Dry-run never writes a release. Do not apply any production database migration for this loop.
The acceptance version `v4-citylab-offline-01` already exists and cannot be overwritten. The Lab
now opens that newer baseline. Older saved overlays remain intact; revert/re-review stale corrections
against the synchronized baseline before exporting them. Export can be scoped to stable IDs in the UI
or with repeated `--place-id` CLI arguments.

From YatraCanvas, re-sync and build the corrected APK:

```powershell
..\YatraCanvas-DataFactory\.venv\Scripts\python.exe tools\sync_city_pack.py --city Jaipur --allow-test-media
flutter build apk --flavor regular --release
flutter run --flavor regular --release -d <adb-device-id>
```

`[PARTIAL]` The existing Android release build uses debug signing. This is a local install artifact,
not a store-signed release. No signing/deployment configuration was changed.

## Physical-phone airplane-mode acceptance

1. Connect an Android phone, enable USB debugging, and confirm `adb devices -l` lists it.
2. Install the built APK from YatraCanvas in PowerShell:

   ```powershell
   $adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
   & $adb devices -l
   & $adb install -r build\app\outputs\flutter-apk\app-regular-release.apk
   ```
3. Clear app data for a first-install check if desired; enable airplane mode before launching.
4. Select Jaipur, complete preparation, browse categories, search Jantar Mantar and Suraj Pol Gate,
   and open details. Expect bundled specific photos or an immediate existing fallback.
5. Select several POIs, set dates and an arrival/custom coordinate, create the trip and inspect
   TripDays. Generate the itinerary. Unknown hours remain usable; verify a known-hours stop fits
   its source window. Coordinate markers can appear while online basemap tiles are unavailable.
6. Close and relaunch in airplane mode; reopen the saved trip and itinerary.
7. Install a later APK containing a new pack, relaunch and confirm the repair. Existing runtime
   enrichment/trips live in separate databases; old itineraries require explicit replanning after
   a pack upgrade. For stable IDs/version diagnostics use a debug build with
   `flutter run --flavor regular --debug -d <adb-device-id>`; release UI omits the diagnostic panel.

From City Lab, the current metadata-driven sync and launch commands are:

```powershell
..\YatraCanvas-DataFactory\.venv\Scripts\python.exe tools\sync_city_packs.py --source ..\YatraCanvas-DataFactory --cities jaipur
flutter run -d windows
```

`[UNKNOWN]` Phone latency/battery behavior is not inferred from desktop tests. Record device model,
Android version, cold/warm preparation, search/category/details timings and screenshot evidence.
No physical phone was connected during this implementation; see the implementation report.
