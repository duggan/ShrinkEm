# Slimreel

Slimreel is a macOS app for people whose iCloud storage is full of videos. It lists the
Photos library's videos biggest first and lets you Keep, Delete, Move to Folder, or
Shrink each one. Brand, voice and artwork are specified in `docs/BRAND.md`: calm and
exact, lightly warm; no jokes near deletion; never "clean", "junk" or "optimize".

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
- **Move to Folder** (`Library.export`) writes with `PHAssetResourceManager.writeData`,
  checks the on-disk size equals the resource's size, sets the file dates to the
  capture date and permissions to 644 (Photos writes 600), and removes partial files on
  failure. File names come from `FileNaming.safeName` (adds an extension when the
  original has none, e.g. `PETKIT Video…`) and `uniqueURL` (never overwrites).
- **Free space** (`Library.freeSpace`): `volumeAvailableCapacityForImportantUsage` is 0
  on SMB/network volumes; fall back to `volumeAvailableCapacity`.
- **Shrink** (`Shrink.swift`, rules in `SlimreelKit/ShrinkRules.swift`): Photos can't
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
- **Kept** marks are local (`UserDefaults` key `kept`, by local identifier) and carried
  over to a shrunk replacement.

## Layout

- `Sources/SlimreelKit/`: pure logic with unit tests: `Formatting` (`fmtBytes`,
  `fmtDur`), `FileNaming`, `DateRange` and `MonthBucket`, `ShrinkRules`
  (`ShrinkSettings`, `plan`, `worthReplacing`, presets).
- `Sources/SlimreelApp/`:
  - `App.swift`: the app and `Brand` colours (accent is Mint deep `#1FA588`).
  - `Library.swift`: `VideoItem`, scanning, delete, album, Keep, Move to Folder.
  - `Shrink.swift`: re-encode, import, the shrink workflow, `ShrinkOptionsSheet`.
  - `ContentView.swift`: filter row (date range first), timeline, table, toolbar,
    dialogs, empty states.
  - `Timeline.swift`: `SizeTimeline` (Swift Charts, square-root y scale so one huge month
    doesn't flatten the rest; fixed ticks 1/5/10/20/50… GB; drag selects a month range;
    hover readout above the plot) and `DateRangeControls` (presets, pickers, clear).
  - `MoveSheet.swift`: progress and summary for Move and Shrink.
  - `DetailView.swift`: preview, metadata, `Thumb`, `PlayerView`.
  - `Media.swift`: thumbnails, frame rate (local only), player items.
- `PlayerView` wraps `AVPlayerView`. Don't switch to SwiftUI's `VideoPlayer`: it
  crashed at first display (`getSuperclassMetadata` in `_AVKit_SwiftUI`), same as in
  Subya. AVKit is linked explicitly in `Package.swift`.
- `Resources/App.entitlements` must keep
  `com.apple.security.personal-information.photos-library`: the hardened runtime blocks
  Photos access without it.

## Developer hooks (environment variables, read-only, quit when done)

- `SLIMREEL_SELFTEST_DIR=<dir>`: exports the smallest plain and edited videos twice
  (checks naming) into `<dir>`, logs to `selftest.log`. Deletes nothing.
- `SLIMREEL_SHRINKTEST_DIR=<dir>`: re-encodes a few 4K videos (landscape, portrait,
  edited, high bitrate) into `<dir>` without touching the library; add
  `SLIMREEL_SHRINKTEST_LOW=1` for 720p/30 and `SLIMREEL_SHRINKTEST_ARCHIVE=1` to also
  export originals. Logs to `shrinktest.log`.
- `SLIMREEL_RENDER_DIR=<dir>`: renders the timeline with real data to PNGs (light, dark,
  with a range) via `ImageRenderer`. Slow on a big library; give it a few minutes.

Run with `open -n --env NAME=value build/Slimreel.app`.

## Building and releasing

- `make run`, `test`, `icons`, `dmg`, `release` (see the Makefile). Universal, Developer
  ID, hardened runtime, not sandboxed, bundle ID `ie.duggan.Slimreel`, notary profile
  `slimreel`.
- `.github/workflows/release.yml` (tags `v*`, `test/**` branches, manual) and `ci.yml`,
  as in Subya and NanoNeo. Secrets and steps: `docs/RELEASING.md`. Bump
  `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/App-Info.plist`
  before tagging.
- Artwork: `Resources/art/make_icons.py` and `make_banner.py` (see their docstrings);
  `make icons` renders `Slimreel.icns` and the DMG background. Commit the outputs.
- Website: `docs/index.html` on GitHub Pages.
