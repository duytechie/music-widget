# Album Artwork

A small native macOS app that shows the current album cover from Apple Music or Spotify on the desktop. The artwork tile is 164 × 164 points, with rounded corners and no playback controls. Requires macOS 14 or newer.

## Build and launch

With Xcode's command line tools selected:

```sh
bash scripts/build.sh
open "build/Album Artwork.app"
```

The build script creates a release `.app` and signs it locally with an ad hoc signature and the Apple Events entitlement. It uses only Apple's frameworks, has no package dependencies, and does not enable App Sandbox. It builds for the current Mac's architecture. For source editing, open `Package.swift` in Xcode; run the bundled `.app` for normal use, rather than the unbundled SwiftPM executable.

## Use

- Open Apple Music or Spotify and play a song. The app never launches either player or changes playback itself.
- When both players are running, whichever is playing is shown. If both are idle, the last shown player is kept, so quitting one never swaps in the other's paused cover.
- Allow the request to read Music and/or Spotify if macOS shows an Automation prompt (one per player).
- Drag anywhere on the cover. In open desktop space it stays where you release it. Near another desktop widget or a screen edge, a rounded outline shows the proposed drop position. Move away to dismiss the outline, or release to snap into it. Position and visibility persist across launches.
- Click the stacked-square icon in the menu bar for **Launch at Login**, **Show/Hide Artwork**, **Reset Position**, and **Quit Album Artwork**. The same menu is available by right-clicking the tile.
- The cover remains visible when Music pauses, stops, or closes. A saved cover also appears after restarting this app.
- A new track without readable artwork shows a neutral music-note tile. Artwork retries after 1, 2, 4, 8, and 16 seconds, then waits for a different track.
- If access is denied, the menu exposes **Open Automation Settings…** and **Retry Music Access**. Enable Music access for the requesting app in **System Settings → Privacy & Security → Automation**, then retry. When launched from a development tool, macOS may attribute the request to that tool.

The tile stays behind ordinary application windows and is configured for desktop Spaces, not full-screen app Spaces. It is a desktop app, so it does not appear in macOS's Edit Widgets gallery. Launch at Login is an opt-in menu toggle using `SMAppService.mainApp`. There is no Dock icon, server, analytics, or catalog API integration. Spotify covers are downloaded from the image URL Spotify itself reports (`artwork url`); only HTTPS URLs on Spotify's image CDNs (`*.scdn.co`, `*.spotifycdn.com`) are fetched, with an ephemeral session, 5-second timeout and 10 MB cap. No Spotify account, API key or Web API call is involved.

## Local storage and implementation

Player metadata is polled once per second for each running player (`Scripts/metadata.js` for Music, `Scripts/spotify-metadata.js` for Spotify). Player selection and Spotify URL validation live in `ArtworkCore/PlayerSource.swift`; the download is `SpotifyArtworkLoader.swift`. For Music, JXA reads metadata and AppleScript extracts the raw image through Music's scripting interface. Requests are serialized, time out after five seconds, and are cancelled on exit. The first metadata request (and an explicit permission retry) allows 60 seconds for the system permission prompt. Artwork requests check track identity before/after extraction, then verify metadata again before display.

The latest successful cover and track metadata are stored together in `~/Library/Application Support/AlbumArtwork/last-artwork.json`. Window position and hidden state use the app's preferences domain, `com.local.AlbumArtwork`. When a new track is detected, the previous cover cache is removed so an unrelated album is not restored later. No library modification or catalog request is performed.

## Verification

```sh
bash scripts/test.sh
codesign --verify --strict "build/Album Artwork.app"
```

Automated tests cover pause/stop/close retention, stale results after rapid skipping, bounded retries, metadata escaping, permission-error detection, subprocess failure/timeout/cancellation, and screen-placement recovery.

See [VALIDATION.md](VALIDATION.md) for live test results and remaining manual checks. Ad hoc signing is intended for this local prototype; distribution and notarization are outside its scope. Rebuilding can cause macOS to request Automation permission again.

## Copyright and Demo Assets

- Do not use copyrighted commercial album artwork in README screenshots, documentation, or promotional materials without appropriate permission or another valid legal basis.
- Prefer original, fictional album artwork for demonstrations.
- Do not download and redistribute album artwork from Apple Music as repository assets.
- Keep demo assets separate from artwork retrieved during normal app operation.
- Clearly label simulated app screenshots or mockups when applicable.
