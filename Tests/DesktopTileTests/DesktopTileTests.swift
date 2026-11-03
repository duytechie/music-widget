import AppKit
import ArtworkCore
import XCTest
@testable import AlbumArtwork

final class DesktopTileTests: XCTestCase {
    @MainActor func testDragFollowsPointerUntilReleaseAndRestoresDroppedCell() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("A WindowServer display is required") }
        _ = NSApplication.shared
        let name = "com.local.AlbumArtwork.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "tileHidden")
        let tile = DesktopTile(store: ArtworkStore(), defaults: defaults)
        let window = tile.window
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        let grab = CGPoint(x: 50, y: 67)
        let surface = try XCTUnwrap(view.hitTest(grab))
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }

        let initial = window.frame
        let desired = CGRect(x: floor(screen.visibleFrame.midX) - 37, y: floor(screen.visibleFrame.midY) - 19,
                             width: window.frame.width, height: window.frame.height)
        let target = TilePlacement.fit(desired, visibleScreens: NSScreen.screens.map(\.visibleFrame),
                                       widgets: DesktopWidgetFrames.current())
        XCTAssertNotEqual(window.frame, target)
        let pointer = CGPoint(x: desired.minX + grab.x, y: desired.minY + grab.y)
        surface.mouseDown(with: try mouse(.leftMouseDown, at: window.convertPoint(toScreen: grab)))
        XCTAssertFalse(tile.dropGuide.isVisible)
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        XCTAssertEqual(window.frame, desired)
        XCTAssertTrue(tile.dropGuide.isVisible)
        XCTAssertEqual(tile.dropGuide.frame.insetBy(dx: 4, dy: 4), target)
        XCTAssertTrue(tile.dropGuide.ignoresMouseEvents)
        XCTAssertEqual(defaults.double(forKey: "tileX"), initial.minX)
        XCTAssertEqual(defaults.double(forKey: "tileY"), initial.minY)
        // Keep dragging across a cell boundary. The guide must update before the drop.
        let next = desired.offsetBy(dx: -TilePlacement.pitch, dy: 0)
        let nextPointer = CGPoint(x: next.minX + grab.x, y: next.minY + grab.y)
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: nextPointer))
        XCTAssertEqual(window.frame, next)
        let nextTarget = TilePlacement.fit(next, visibleScreens: NSScreen.screens.map(\.visibleFrame),
                                           widgets: DesktopWidgetFrames.current())
        XCTAssertNotEqual(nextTarget, target)
        XCTAssertEqual(tile.dropGuide.frame.insetBy(dx: 4, dy: 4), nextTarget)
        surface.mouseUp(with: try mouse(.leftMouseUp, at: nextPointer))
        XCTAssertEqual(window.frame, nextTarget)
        XCTAssertFalse(tile.dropGuide.isVisible)
        let restored = DesktopTile(store: ArtworkStore(), defaults: defaults)
        XCTAssertEqual(restored.window.frame, nextTarget)
    }
}
