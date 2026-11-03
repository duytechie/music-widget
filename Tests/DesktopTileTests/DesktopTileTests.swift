import AppKit
import ArtworkCore
import XCTest
@testable import AlbumArtwork

final class DesktopTileTests: XCTestCase {
    @MainActor func testDragTransitionsBetweenGuidedAndFreePlacement() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("A WindowServer display is required") }
        _ = NSApplication.shared
        let name = "com.local.AlbumArtwork.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "tileHidden")
        let tile = DesktopTile(store: ArtworkStore(), defaults: defaults, widgetFrames: { [] })
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
        let desired = CGRect(x: screen.visibleFrame.minX + 21, y: screen.visibleFrame.maxY - 190,
                             width: window.frame.width, height: window.frame.height)
        let target = TilePlacement.fit(desired, visibleScreens: NSScreen.screens.map(\.visibleFrame))
        XCTAssertNotEqual(window.frame, target)
        let pointer = CGPoint(x: desired.minX + grab.x, y: desired.minY + grab.y)
        surface.mouseDown(with: try mouse(.leftMouseDown, at: window.convertPoint(toScreen: grab)))
        XCTAssertFalse(tile.dropGuide.isVisible)
        let wobble = window.convertPoint(toScreen: CGPoint(x: grab.x + 1, y: grab.y))
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: wobble))
        XCTAssertEqual(window.frame, initial)
        XCTAssertFalse(tile.dropGuide.isVisible)
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        XCTAssertEqual(window.frame, desired)
        XCTAssertTrue(tile.dropGuide.isVisible)
        XCTAssertEqual(tile.dropGuide.frame.insetBy(dx: 4, dy: 4), target)
        XCTAssertTrue(tile.dropGuide.ignoresMouseEvents)
        XCTAssertEqual(defaults.double(forKey: "tileX"), initial.minX)
        XCTAssertEqual(defaults.double(forKey: "tileY"), initial.minY)
        surface.mouseUp(with: try mouse(.leftMouseUp, at: pointer))
        XCTAssertEqual(window.frame, target)
        XCTAssertFalse(tile.dropGuide.isVisible)

        // Leave the corner during the next drag, then release in open space.
        surface.mouseDown(with: try mouse(.leftMouseDown, at: window.convertPoint(toScreen: grab)))
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        XCTAssertTrue(tile.dropGuide.isVisible)
        let next = CGRect(x: floor(screen.visibleFrame.midX) - 37, y: floor(screen.visibleFrame.midY) - 19,
                          width: initial.width, height: initial.height)
        let nextPointer = CGPoint(x: next.minX + grab.x, y: next.minY + grab.y)
        surface.mouseDragged(with: try mouse(.leftMouseDragged, at: nextPointer))
        XCTAssertEqual(window.frame, next)
        XCTAssertFalse(tile.dropGuide.isVisible)
        XCTAssertEqual(defaults.double(forKey: "tileX"), target.minX)
        surface.mouseUp(with: try mouse(.leftMouseUp, at: nextPointer))
        XCTAssertEqual(window.frame, next)
        XCTAssertFalse(tile.dropGuide.isVisible)
        // A widget added near this free drop later should not pull it out of place on launch.
        let newNeighbor = next.offsetBy(dx: TilePlacement.pitch + 10, dy: 0)
        let restored = DesktopTile(store: ArtworkStore(), defaults: defaults, widgetFrames: { [newNeighbor] })
        XCTAssertEqual(restored.window.frame, next)
    }
}
