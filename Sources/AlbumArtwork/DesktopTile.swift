import AppKit
import ArtworkCore
import SwiftUI

struct ArtworkView: View {
    @ObservedObject var store: ArtworkStore
    let place: (CGRect, [CGRect]) -> Void

    var body: some View {
        ZStack {
            if let image = store.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.19), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: DesktopTile.side, height: DesktopTile.side)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.track.map { "\($0.album), \($0.artist)" } ?? "Apple Music artwork")
        .help(store.status)
        .overlay {
            DragSurface(place: place)
                .accessibilityHidden(true)
                .allowsHitTesting(true)
        }
    }
}

private struct DragSurface: NSViewRepresentable {
    let place: (CGRect, [CGRect]) -> Void
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.place = place }
}

private final class DragView: NSView {
    var place: ((CGRect, [CGRect]) -> Void)?
    private var grabOffset = CGPoint.zero
    private var widgets: [CGRect] = []
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        // Keep the original grab point even when the window jumps to another cell.
        grabOffset = event.locationInWindow
        widgets = DesktopWidgetFrames.current()
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        dragged = true
        placeAtPointer(event)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { placeAtPointer(event) }
        dragged = false
    }
    private func placeAtPointer(_ event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        place?(CGRect(x: point.x - grabOffset.x, y: point.y - grabOffset.y,
                      width: window.frame.width, height: window.frame.height), widgets)
    }
    override func menu(for event: NSEvent) -> NSMenu? { window?.contentView?.menu }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopTile: NSObject {
    static let side = TilePlacement.side
    let window: DesktopWindow
    private let defaults: UserDefaults

    init(store: ArtworkStore, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        window = DesktopWindow(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.title = "Album Artwork"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.isMovableByWindowBackground = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone, .fullScreenDisallowsTiling]
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: ArtworkView(store: store) { [weak self] frame, widgets in
            self?.place(frame, widgets: widgets)
        })
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !defaults.bool(forKey: "tileHidden") { window.orderFrontRegardless() }
    }

    var isVisible: Bool { window.isVisible }

    func toggle() {
        if isVisible { window.orderOut(nil) } else { fitOnscreen(); window.orderFrontRegardless() }
        defaults.set(!window.isVisible, forKey: "tileHidden")
    }

    func resetPosition() {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        place(CGRect(x: visible.maxX - Self.side, y: visible.maxY - Self.side, width: Self.side, height: Self.side))
    }

    private func restorePosition() {
        if defaults.object(forKey: "tileX") != nil, defaults.object(forKey: "tileY") != nil {
            let x = defaults.double(forKey: "tileX")
            let y = defaults.double(forKey: "tileY")
            if x.isFinite && y.isFinite {
                place(CGRect(origin: CGPoint(x: x, y: y), size: window.frame.size))
                return
            }
        }
        resetPosition()
    }

    @objc private func screenChanged() { fitOnscreen() }

    private func fitOnscreen() { place(window.frame) }

    private func place(_ frame: CGRect, widgets: [CGRect]? = nil) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !screens.isEmpty else { return }
        let origin = TilePlacement.fit(frame, visibleScreens: screens, widgets: widgets ?? DesktopWidgetFrames.current()).origin
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
        if defaults.object(forKey: "tileX") == nil || defaults.object(forKey: "tileY") == nil ||
            defaults.double(forKey: "tileX") != origin.x || defaults.double(forKey: "tileY") != origin.y {
            savePosition()
        }
    }

    private func savePosition() {
        defaults.set(window.frame.origin.x, forKey: "tileX")
        defaults.set(window.frame.origin.y, forKey: "tileY")
    }
}
