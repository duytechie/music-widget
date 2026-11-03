# Album Artwork

A small native macOS app that shows Apple Music's current album cover on the desktop. The artwork tile is 164 × 164 points, with rounded corners and no playback controls. Requires macOS 14 or newer.

## Build and launch

With Xcode's command line tools selected:

```sh
bash scripts/build.sh
open "build/Album Artwork.app"
```

The build script creates a release `.app` and signs it locally with an ad hoc signature and the Apple Events entitlement. It uses only Apple's frameworks, has no package dependencies, and does not enable App Sandbox. It builds for the current Mac's architecture. For source editing, open `Package.swift` in Xcode; run the bundled `.app` for normal use, rather than the unbundled SwiftPM executable.

## Use

- Open Apple Music and play a song. The app never launches Music or changes playback itself.
- Allow the request to read Music if macOS shows an Automation prompt.
- Drag anywhere on the cover. The cover follows your pointer while a translucent rounded outline marks the nearest available grid cell. Release the mouse or trackpad to snap the cover into the outline, aligned with your desktop widgets. On a display without detectable widgets, the grid starts near the top-left of the usable desktop. Position and visibility persist across launches.
- Click the stacked-square icon in the menu bar for **Show/Hide Artwork**, **Reset Position**, and **Quit Album Artwork**. The same menu is available by right-clicking the tile.
- The cover remains visible when Music pauses, stops, or closes. A saved cover also appears after restarting this app.
- A new track without readable artwork shows a neutral music-note tile. Artwork retries after 1, 2, 4, 8, and 16 seconds, then waits for a different track.
- If access is denied, the menu exposes **Open Automation Settings…** and **Retry Music Access**. Enable Music access for the requesting app in **System Settings → Privacy & Security → Automation**, then retry. When launched from a development tool, macOS may attribute the request to that tool.

The tile stays behind ordinary application windows and is configured for desktop Spaces, not full-screen app Spaces. It is a desktop app, so it does not appear in macOS's Edit Widgets gallery. There is no Dock icon, launch-at-login registration, server, analytics, or catalog API integration.

## Local storage and implementation

Music metadata is polled once per second while Music is running. JXA reads metadata and AppleScript extracts the raw image through Music's scripting interface. Requests are serialized, time out after five seconds, and are cancelled on exit. The first metadata request (and an explicit permission retry) allows 60 seconds for the system permission prompt. Artwork requests check track identity before/after extraction, then verify metadata again before display.

The latest successful cover and track metadata are stored together in `~/Library/Application Support/AlbumArtwork/last-artwork.json`. Window position and hidden state use the app's preferences domain, `com.local.AlbumArtwork`. When a new track is detected, the previous cover cache is removed so an unrelated album is not restored later. No library modification or catalog request is performed.

## Verification

```sh
bash scripts/test.sh
codesign --verify --strict "build/Album Artwork.app"
```

Automated tests cover pause/stop/close retention, stale results after rapid skipping, bounded retries, metadata escaping, permission-error detection, subprocess failure/timeout/cancellation, and screen-placement recovery.

See [VALIDATION.md](VALIDATION.md) for live test results and remaining manual checks. Ad hoc signing is intended for this local prototype; distribution and notarization are outside its scope. Rebuilding can cause macOS to request Automation permission again.
