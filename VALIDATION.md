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
- After installing the grid update, the restored artwork's top-left was (1332, 442) in WindowServer coordinates. The visible faces of the two small desktop widgets started at (1332, 622) and (1332, 802): all three share a column with 16-point gaps.
- Reopened Music after that check, returned to the original playlist, and restored the original random track paused at approximately 1:51. The prototype remains running.

## Automated

All **15 tests passed** with a display available. Geometry tests cover free placement in open space, alignment beside independently positioned and multi-cell widgets, occupied slots, screen edges, and display recovery. Synthetic AppKit mouse events check that a slight pointer wobble leaves the tile still, the cover tracks the grab point, and the guide appears near a corner and disappears in open space. The test verifies both kinds of drop and restores a free position after relaunch. The release build passed local code-signature verification.

The interaction follows macOS desktop placement guidance. The app uses its own snap distances of 60 points around adjacent widget slots and 32 points around inset edge rows or columns. [Apple’s widget guide](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac) · [Desktop drag demonstration](https://macmost.com/19-tips-for-using-desktop-widgets-on-your-mac.html)

## Manual checks

The following still need explicit live verification and must not be inferred solely from the window configuration or unit tests:

- Desktop layering, Show Desktop, multiple Spaces, and exclusion from full-screen app Spaces.
- Physical pointer dragging: the UI automation service cannot drive coordinate drags on this desktop-level window (`noWindowsAvailable`), though it can inspect the view and invoke its context menu.
- Hide/show through the menu bar icon.
- Physical display disconnect/reconnect.
- A clean first-launch denied Automation permission flow, without changing the developer's existing permissions.

These manual limitations are separate from the passing automated geometry and state-machine checks.

## Main-display placement correction

- Read the live LG ULTRAFINE (2560 × 1440) and built-in display (1512 × 982) geometry and native desktop-widget bounds. The two small widget faces occupied a right-edge column, at 16 and 196 points above the external display bottom; the artwork was at 376 points. This establishes the intended 16-point gaps in this user's layout.
- Artwork placed on the primary display now follows the primary-display role. Explicit placement on a secondary display retains physical-display identity. Insets are saved from the nearest horizontal and vertical edges, so the bottom-right group does not shift with a change in display height.
- Display notifications trigger immediate restoration plus cancellable rechecks over two seconds, to handle subsequent window relocation and native-widget reflow. Automatic restoration does not overwrite the saved placement.
- All **17 tests passed**, including simulated primary-display swaps in both directions using the observed display sizes, legacy preference migration, bottom-right spacing, and a late window move. Release build and signature verification also pass.
- Live bounds were inspected; an actual main-display switch and physical unplug/replug still require verification. The automated swap is not a physical display test.

Apple documents the primary screen and changing coordinate origin in [NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens), and free desktop placement in [its widget guide](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac). Neither document specifies the complete private widget-layout migration algorithm; the behavior above implements the requested main-display policy using observed geometry.
