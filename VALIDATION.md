# Prototype validation

Tested on the development Mac, macOS 26.7.1, using Xcode 26.6.

## Confirmed live

- Extracted a valid 600 × 600 JPEG from a random Apple Music subscription track using the bundled artwork script.
- Launched the locally signed `.app` and visually verified its rounded, artwork-only tile. The captured window is 328 × 328 pixels on the Retina display, corresponding to 164 × 164 points.
- Played a random track from an Apple Music catalog album displaying **Add to Library**. The prototype displayed the album artwork without adding the album or song to the library.
- Changed to another random track from that catalog album. From the first externally observed metadata change to the matching persisted cover, the measured delay was **2.035 seconds**. This is an approximate observation, not a guaranteed refresh deadline; Music may take longer to provide artwork.
- Paused that streamed song and verified that the same cover remained visible, with the paused track reflected in accessibility help.
- Restored the original random track, paused at approximately 1:51, and returned to the original playlist.
- Closed Music and verified that the album cover remained visible with **Apple Music is closed · keeping last cover** in the controls menu.
- Opened the tile's controls menu, invoked **Reset Position**, and quit the prototype using **Quit Album Artwork**.
- Relaunched the final build while Music was closed: the saved album cover and placement restored, and the status still reported Music closed. The prototype did not launch Music.
- Reopened Music after that check, returned to the original playlist, and restored the original random track paused at approximately 1:51. The prototype remains running.

## Automated

All **10 tests passed**. The suite checks retention, stale generations, retry scheduling, Unicode/quoted metadata, permission errors, subprocess output/failure/timeout/cancellation, and recovery when a display disappears or has negative coordinates. The final release build passed local code-signature verification.

## Manual checks

The following still need explicit live verification and must not be inferred solely from the window configuration or unit tests:

- Desktop layering, Show Desktop, multiple Spaces, and exclusion from full-screen app Spaces.
- Dragging and saved drag placement: the UI automation service cannot drive coordinate drags on this desktop-level window (`noWindowsAvailable`), though it can inspect the view and invoke its context menu.
- Hide/show through the menu bar icon.
- Physical display disconnect/reconnect and placement against other actual desktop widgets.
- A clean first-launch denied Automation permission flow, without changing the developer's existing permissions.

These manual limitations are separate from the passing automated geometry and state-machine checks.
