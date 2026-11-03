import AppKit
import ArtworkCore
import XCTest
@testable import AlbumArtwork

final class DesktopTileTests: XCTestCase {
    @MainActor func testDragSnapsWhileMovingAndRestoresDroppedCell() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("A WindowServer display is required") }
        _ = NSApplication.shared
        let name = "com.local.AlbumArtwork.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "tileHidden")
        let tile = DesktopTile(store: ArtworkStore(), defaults: defaults)
        let window = tile.window
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        let grab = CGPoint(x: 50, y: 67)
        let surface = try XCTUnwrap(view.hitTest(grab))
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }

        let desired = CGRect(x: screen.visibleFrame.midX - 37, y: screen.visibleFrame.midY - 19,
                             width: window.frame.width, height: window.frame.height)
        let target = TilePlacement.fit(desired, visibleScreens: NSScreen.screens.map(\.visibleFrame),
                                       widgets: DesktopWidgetFrames.current())
        XCTAssertNotEqual(window.frame, target)
        let pointer = CGPoint(x: desired.minX + grab.x, y: desired.minY + grab.y)
        surface.mouseDown(with: try mouse(.leftMouseDown, at: window.convertPoint(toScreen: grab)))
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        XCTAssertEqual(window.frame, target)
        surface.mouseUp(with: try mouse(.leftMouseUp, at: pointer))
        XCTAssertEqual(window.frame, target)
        let restored = DesktopTile(store: ArtworkStore(), defaults: defaults)
        XCTAssertEqual(restored.window.frame, target)
    }
}
