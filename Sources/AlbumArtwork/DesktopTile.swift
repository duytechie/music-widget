import AppKit
import ArtworkCore
import SwiftUI

struct ArtworkView: View {
    @ObservedObject var store: ArtworkStore

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
            DragSurface()
                .accessibilityHidden(true)
                .allowsHitTesting(true)
        }
    }
}

private struct DragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func menu(for event: NSEvent) -> NSMenu? { window?.contentView?.menu }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopTile: NSObject, NSWindowDelegate {
    static let side: CGFloat = 164
    let window: DesktopWindow
    private let defaults = UserDefaults.standard
    private var restoring = false

    init(store: ArtworkStore) {
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
        window.isMovableByWindowBackground = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone, .fullScreenDisallowsTiling]
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: ArtworkView(store: store))
        window.delegate = self
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
        window.setFrameOrigin(NSPoint(x: visible.maxX - Self.side - 24, y: visible.maxY - Self.side - 24))
        savePosition()
    }

    func windowDidMove(_ notification: Notification) {
        if !restoring { savePosition() }
    }

    private func restorePosition() {
        restoring = true
        defer { restoring = false }
        if defaults.object(forKey: "tileX") != nil, defaults.object(forKey: "tileY") != nil {
            let x = defaults.double(forKey: "tileX")
            let y = defaults.double(forKey: "tileY")
            if x.isFinite && y.isFinite { window.setFrameOrigin(NSPoint(x: x, y: y)) }
            fitOnscreen()
        } else {
            resetPosition()
        }
    }

    @objc private func screenChanged() { fitOnscreen() }

    private func fitOnscreen() {
        let fitted = TilePlacement.fit(window.frame, visibleScreens: NSScreen.screens.map(\.visibleFrame))
        window.setFrameOrigin(fitted.origin)
        savePosition()
    }

    private func savePosition() {
        defaults.set(window.frame.origin.x, forKey: "tileX")
        defaults.set(window.frame.origin.y, forKey: "tileY")
    }
}
