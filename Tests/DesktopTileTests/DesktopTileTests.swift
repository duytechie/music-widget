import AppKit
import ArtworkCore
import XCTest
@testable import AlbumArtwork

final class DesktopTileTests: XCTestCase {
    @MainActor func testDisplayReconfigurationPreservesPreferredPosition() throws {
        _ = NSApplication.shared
        let name = "com.local.AlbumArtwork.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "tileHidden")
        defaults.set("external", forKey: "tileDisplayID")
        defaults.set(false, forKey: "tileFollowsPrimary")
        defaults.set("right", forKey: "tileHorizontalEdge")
        defaults.set(36.0, forKey: "tileHorizontalInset")
        defaults.set("top", forKey: "tileVerticalEdge")
        defaults.set(56.0, forKey: "tileVerticalInset")
        defaults.set(36.0, forKey: "tileRight")
        defaults.set(56.0, forKey: "tileTop")
        let laptop = DesktopTile.Display(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        var screens = [laptop, DesktopTile.Display(id: "external",
            visibleFrame: CGRect(x: 1440, y: 200, width: 2560, height: 1415))]
        let tile = DesktopTile(store: ArtworkStore(), defaults: defaults, widgetFrames: { [] }, displays: { screens })
        func expected(_ display: DesktopTile.Display) -> CGRect {
            CGRect(x: display.visibleFrame.maxX - 200, y: display.visibleFrame.maxY - 220, width: 164, height: 164)
        }
        XCTAssertEqual(tile.window.frame, expected(screens[1]))

        // The same display becomes primary, changes scaling, and moves above/left.
        let external = DesktopTile.Display(id: "external",
            visibleFrame: CGRect(x: -1920, y: 875, width: 1920, height: 1055))
        screens = [external, laptop]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(tile.window.frame, expected(external))

        screens = [laptop]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(tile.window.frame, expected(laptop))
        XCTAssertEqual(defaults.string(forKey: "tileDisplayID"), "external")
        XCTAssertEqual(defaults.double(forKey: "tileRight"), 36)
        XCTAssertEqual(defaults.double(forKey: "tileTop"), 56)

        screens = [laptop, external]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(tile.window.frame, expected(external))
        let restored = DesktopTile(store: ArtworkStore(), defaults: defaults, widgetFrames: { [] }, displays: { screens })
        XCTAssertEqual(restored.window.frame, expected(external))
    }

    @MainActor func testBottomRightWidgetGroupFollowsMainDisplay() async throws {
        _ = NSApplication.shared
        let name = "com.local.AlbumArtwork.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "tileHidden")
        // Reproduce the user's legacy saved position on the external display.
        defaults.set("external", forKey: "tileDisplayID")
        defaults.set(16.0, forKey: "tileRight")
        defaults.set(870.0, forKey: "tileTop")
        var screens = [DesktopTile.Display(id: "external", visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1410)),
                       DesktopTile.Display(id: "laptop", visibleFrame: CGRect(x: -1512, y: 302, width: 1512, height: 950))]
        func group(on display: DesktopTile.Display) -> [CGRect] {
            [16.0, 196.0].map { CGRect(x: display.visibleFrame.maxX - 180,
                                     y: display.visibleFrame.minY + $0, width: 164, height: 164) }
        }
        var widgets = group(on: screens[0])
        let tile = DesktopTile(store: ArtworkStore(), defaults: defaults, widgetFrames: { widgets }, displays: { screens })
        XCTAssertEqual(tile.window.frame.origin, CGPoint(x: 2380, y: 376))
        XCTAssertTrue(defaults.bool(forKey: "tileFollowsPrimary"))
        XCTAssertEqual(defaults.string(forKey: "tileVerticalEdge"), "bottom")
        XCTAssertEqual(defaults.double(forKey: "tileVerticalInset"), 376)

        screens = [DesktopTile.Display(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950)),
                   DesktopTile.Display(id: "external", visibleFrame: CGRect(x: 1512, y: -302, width: 2560, height: 1410))]
        widgets = group(on: screens[0])
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(tile.window.frame.origin, CGPoint(x: 1332, y: 376))
        XCTAssertEqual(tile.window.frame.minY - widgets[1].maxY, 16)
        // Simulate AppKit moving the window again after the notification.
        tile.window.setFrameOrigin(CGPoint(x: 400, y: 400))
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(tile.window.frame.origin, CGPoint(x: 1332, y: 376))

        screens = [DesktopTile.Display(id: "external", visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1410)), screens[0]]
        widgets = group(on: screens[0])
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(tile.window.frame.origin, CGPoint(x: 2380, y: 376))
        XCTAssertEqual(defaults.double(forKey: "tileVerticalInset"), 376)
    }

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
