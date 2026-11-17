# ShrinkEm

ShrinkEm is a macOS app for people whose iCloud storage is full of videos. It lists the
Photos library's videos biggest first and lets you Keep, Delete, Move to Folder, or
Shrink each one. Brand, voice and artwork are specified in `docs/BRAND.md`: calm and
exact, lightly warm; no jokes near deletion; never "clean", "junk" or "optimize". It's
a Hyperspecific app (the studio's spec lives outside this repo).

**It was called Slimreel in 1.0.0** (bundle ID `ie.duggan.Slimreel`). It was renamed the
same day because an iOS app called Slimreel does the same job; `docs/BRAND.md` §1 has
the story. The bundle ID is now `dev.hyperspecific.ShrinkEm`. `SettingsMigration` in
`App.swift` copies the Keep marks and the six settings (`minMB`, `hideKept`,
`moveFolder`, `shrinkHeight`, `shrinkFPS`, `shrinkArchive`) from the old domain once,
never overwriting a value the new app already has. Photos access can't move; macOS
asks again. Written `ShrinkEm` everywhere; "Shrink 'Em" is only for speech.

## Design rules

- **Nothing is removed until its replacement is verified**, and every removal goes
  through `PHAssetChangeRequest.deleteAssets`, so Photos asks the user and the video
  lands in Recently Deleted. Keep both properties for any new action.
- **Everything stays on the Mac.** No network calls of our own. Photos may download
  originals from iCloud (`isNetworkAccessAllowed = true`) to preview, move or shrink.
- **Sizes** come from `PHAssetResource`'s `fileSize` via KVC (not public API, but the
  standard way). An item's size is the sum of all its resources.
- **Edited** means Photos holds `.adjustmentData` or a `.fullSizeVideo`. An `.aae`
  sidecar from an import (type 16) is not an edit. When there's adjustment data but no
  rendered `.fullSizeVideo`, Move to Folder renders the edited version itself
  (`renderEdited`, `version = .current`) as `NAME (edited).mov`, or the edit (e.g. a
  slow-mo speed change) would be lost.
- **Move to Folder** (`Library.export`) streams each resource with
  `PHAssetResourceManager.requestData` (`Library.write` in `Cancel.swift`; unlike
  `writeData` it can be cancelled mid-file), hashing the stream with SHA-256, then
  `synchronize`s, reads the file back and compares hashes (`SHRINKEM_CORRUPT_COPIES=1`
  damages copies before the read-back, to test that a bad copy is caught and removed).
  It also checks the on-disk size equals the resource's size, sets the file dates to the
  capture date and permissions to 644 (Photos writes 600), and removes partial files on
  failure. File names come from `FileNaming.safeName` (adds an extension when the
  original has none, e.g. `PETKIT Video…`) and `uniqueURL` (never overwrites).
- **Free space** (`Library.freeSpace`): `volumeAvailableCapacityForImportantUsage` is 0
  on SMB/network volumes; fall back to `volumeAvailableCapacity`.
- **Shrink** (`Shrink.swift`, rules in `ShrinkEmKit/ShrinkRules.swift`): Photos can't
  replace a video's file in place (an edit keeps the original too and uses more
  space), so Shrink re-encodes, adds a new asset with the same creation date, location,
  favourite, hidden state and user albums (`importReplacement`), then deletes the
  originals in one batch. Gotchas found the hard way:
  - Photos' `requestExportSession` ignores a custom `videoComposition.frameDuration`.
    Use `requestAVAsset` (`version = .current`) and our own `AVAssetExportSession`.
  - `videoComposition(withPropertiesOf:)` sets `sourceTrackIDForFrameTiming`, which
    overrides `frameDuration`. Set it to `kCMPersistentTrackID_Invalid`.
  - The HEVC 1920×1080 preset keeps HDR (HLG). There's no HEVC 720p preset; 720p is
    H.264 and tone-maps to SDR (checked by eye: looks right).
  - The export keeps one audio track; iPhone spatial audio's second track is dropped.
  - Slow-mo (`.videoHighFrameRate`) is skipped. A copy must be ≥10% smaller
    (`worthReplacing`) and pass a length/video-track check before it's imported.
  - With "save originals first", the original is exported after the re-encode proves
    worthwhile and before anything touches Photos; if that fails the video is untouched.
- **The queue** (`WorkQueue.swift`): Move and Shrink are `Job`s run one at a time by
  `WorkQueue`, while the window stays usable. It's its own `ObservableObject` (owned by
  `Library.queue`) so progress ticks redraw only the queue button and popover, not the
  table; progress callbacks are throttled to 0.5% steps. `Library.busyIDs` (published
  only when it changes) marks videos in waiting or running jobs: they can't be queued
  again or deleted. Each job re-fetches its assets before working on them (skips any
  deleted meanwhile), deletes its verified originals in one batch when it finishes (so
  Photos asks once per job), and Shrink adds the new copies with `Library.addItems`
  instead of rescanning. Cancel (`WorkQueue.cancel`) on a running job fires its
  `CancelToken`, which stops whatever is in flight (`requestData`, `requestAVAsset`,
  `requestExportSession`, `AVAssetExportSession.cancelExport`); the current video is
  left untouched (partials removed) and videos the job already finished still go
  through to deletion, because abandoning finished shrinks would leave both versions.
  Shrink checks the token one last time before importing. Measured: running jobs stop
  in 0.1–0.15 s. "Stop After This Video" (`stopAfterCurrent`) is the gentler option.
  The queue lives in the toolbar (`QueueToolbarButton`, last item, `.primaryAction`): a
  tray, or a progress ring around the job's icon, or a spinner while Photos waits for a
  delete confirmation; the count is in the tooltip and the Dock badge. While the queue runs, `ProcessInfo.beginActivity` keeps App Nap
  and idle sleep away; the Dock badge counts videos left; `AppDelegate` asks before
  quitting (a running Shrink would leave both versions until its job deletes). Measured
  on a 1,945-video library: no main-thread stall over 60 ms while a job runs; ~100-150 ms
  once when a job starts or finishes (the table redraws for `busyIDs`).
- **Main-thread performance** (found from a beachball when queueing many selected
  videos while a job wrote to a network share; `SHRINKEM_STALLTEST_DIR`, below):
  - `ContentView` caches the filtered, sorted rows (`RowsCache`, keyed by `RowsKey`:
    `Library.itemsVersion`/`keptVersion`, filters, dates, sort). Rebuilding them in
    `body` re-sorted the library on every selection change or queue marker, and gave
    the table a new array to re-diff. Sorting uses `ContentView.sorted` (a direct
    comparison per column, ties by id; filenames as Finder sorts them), not
    `sorted(using: KeyPathComparator)`, which was the biggest main-thread cost.
  - Row cells that can change (`Thumb`, `RowFlags`) are `Equatable` and marked
    `.equatable()`, so unchanged rows aren't re-laid-out (the table re-measures row
    heights for every row it thinks changed).
  - Never touch a folder that may be on a network share from the main thread:
    `fileExists` and free space each blocked ~0.8–0.9 s while a job streamed to SMB.
    Use `Library.folderStatus` (off-main); the Shrink sheet shows "Checking the
    folder…" and the Move confirmation is shown once its free-space check returns.
  - Measured after the fix (300 selected rows, a move streaming to SMB): no main-thread
    stall over 100 ms when selecting or queueing (before: ~0.9 s each, worse with more
    rows or repeated queueing).
- **Kept** marks are local (`UserDefaults` key `kept`, by local identifier) and carried
  over to a shrunk replacement.

## Layout

- `Sources/ShrinkEmKit/`: pure logic with unit tests: `Formatting` (`fmtBytes`,
  `fmtDur`), `FileNaming`, `DateRange` and `MonthBucket`, `ShrinkRules`
  (`ShrinkSettings`, `plan`, `worthReplacing`, presets).
- `Sources/ShrinkEmApp/`:
  - `App.swift`: the app and `Brand` colours (accent is Mint deep `#1FA588`).
  - `Library.swift`: `VideoItem`, scanning, delete, album, Keep, Move to Folder.
  - `Shrink.swift`: re-encode, import, `ShrinkOptionsSheet`.
  - `ContentView.swift`: filter row (date range first), timeline, table, toolbar,
    dialogs, empty states.
  - `Timeline.swift`: `SizeTimeline` (Swift Charts, square-root y scale so one huge month
    doesn't flatten the rest; fixed ticks 1/5/10/20/50… GB; drag selects a month range;
    hover readout above the plot) and `DateRangeControls` (presets, pickers, clear).
  - `WorkQueue.swift`: `Job`, `WorkQueue` (runner, move and shrink workflows), test hook.
  - `JobViews.swift`: `QueueToolbarButton`, `QueueIcon`, `QueuePopover`, `JobRow`.
  - `Cancel.swift`: `CancelToken` and the cancellable, read-back-verified `Library.write`.
  - `DetailView.swift`: preview, metadata, `Thumb`, `PlayerView`.
  - `Media.swift`: thumbnails, frame rate (local only), player items.
- `PlayerView` wraps `AVPlayerView`. Don't switch to SwiftUI's `VideoPlayer`: it
  crashed at first display (`getSuperclassMetadata` in `_AVKit_SwiftUI`), same as in
  Subya. AVKit is linked explicitly in `Package.swift`.
- `Resources/App.entitlements` must keep
  `com.apple.security.personal-information.photos-library`: the hardened runtime blocks
  Photos access without it.

## Developer hooks (environment variables, read-only, quit when done)

- `SHRINKEM_SELFTEST_DIR=<dir>`: exports the smallest plain and edited videos twice
  (checks naming) into `<dir>`, logs to `selftest.log`. Deletes nothing.
- `SHRINKEM_SHRINKTEST_DIR=<dir>`: re-encodes a few 4K videos (landscape, portrait,
  edited, high bitrate) into `<dir>` without touching the library; add
  `SHRINKEM_SHRINKTEST_LOW=1` for 720p/30 and `SHRINKEM_SHRINKTEST_ARCHIVE=1` to also
  export originals. Logs to `shrinktest.log`.
- `SHRINKEM_RENDER_DIR=<dir>`: renders the timeline with real data to PNGs (light, dark,
  with a range) via `ImageRenderer`, and the queue popover and toolbar icon states with sample
  jobs via an offscreen `NSHostingView` (`ImageRenderer` draws AppKit-backed controls,
  such as buttons, progress bars and scroll views, as yellow placeholders). Slow on a big
  library; give it a few minutes.
- `SHRINKEM_QUEUETEST_DIR=<dir>`: queues dry-run jobs on real videos (files written to
  `<dir>`, nothing imported or deleted), checks ordering, duplicate and cancel rules and
  `busyIDs`, and logs the longest main-thread stall. Add `SHRINKEM_QUEUETEST_BIG=1` for a
  longer shrink (a ~100 MB 4K video).

- `SHRINKEM_STALLTEST_DIR=<dir>` (optionally `SHRINKEM_STALLTEST_TARGET=<folder>`, e.g. on
  a network share): checks the table's fast sort against the generic one for every
  column, then times the share checks and main-thread stalls while selecting 300 rows
  (via a test-only notification) and queueing them during a dry-run move to the target.
  Pair with `sample <pid> 30 1` to see where the main thread spends its time.

Run with `open -n --env NAME=value build/ShrinkEm.app`.

## Building and releasing

- `make run`, `test`, `icons`, `dmg`, `release` (see the Makefile). Universal, Developer
  ID, hardened runtime, not sandboxed, bundle ID `dev.hyperspecific.ShrinkEm`, notary profile
  `shrinkem`.
- `.github/workflows/release.yml` (tags `v*`, `test/**` branches, manual) and `ci.yml`,
  as in Subya and NanoNeo. Secrets and steps: `docs/RELEASING.md`. Bump
  `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/App-Info.plist`
  before tagging.
- Artwork: `Resources/art/make_icons.py` and `make_banner.py` (see their docstrings);
  `make icons` renders `ShrinkEm.icns` and the DMG background. Commit the outputs.
- Website: `docs/index.html` on GitHub Pages.
