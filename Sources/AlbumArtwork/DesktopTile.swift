import AppKit
import ArtworkCore
import SwiftUI

enum DragPhase { case moving, released }

struct ArtworkView: View {
    @ObservedObject var store: ArtworkStore
    let onDrag: (CGRect, DragPhase) -> Void

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
            DragSurface(onDrag: onDrag)
                .accessibilityHidden(true)
                .allowsHitTesting(true)
        }
    }
}

private struct DragSurface: NSViewRepresentable {
    let onDrag: (CGRect, DragPhase) -> Void
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.onDrag = onDrag }
}

private final class DragView: NSView {
    var onDrag: ((CGRect, DragPhase) -> Void)?
    private var grabOffset = CGPoint.zero
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        grabOffset = event.locationInWindow
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        guard dragged || hypot(point.x - grabOffset.x, point.y - grabOffset.y) >= 3 else { return }
        dragged = true
        placeAtPointer(event, phase: .moving)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { placeAtPointer(event, phase: .released) }
        dragged = false
    }
    private func placeAtPointer(_ event: NSEvent, phase: DragPhase) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        onDrag?(CGRect(x: point.x - grabOffset.x, y: point.y - grabOffset.y,
                      width: window.frame.width, height: window.frame.height), phase)
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
    let dropGuide: DesktopWindow
    private let widgetFrames: @MainActor () -> [CGRect]
    private var dragWidgets: [CGRect]?
    private let defaults: UserDefaults

    init(store: ArtworkStore, defaults: UserDefaults = .standard,
         widgetFrames: @escaping @MainActor () -> [CGRect] = { DesktopWidgetFrames.current() }) {
        self.widgetFrames = widgetFrames
        self.defaults = defaults
        window = DesktopWindow(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.borderless], backing: .buffered, defer: false)
        dropGuide = DesktopWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
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
        dropGuide.backgroundColor = .clear
        dropGuide.isOpaque = false
        dropGuide.hasShadow = false
        dropGuide.ignoresMouseEvents = true
        dropGuide.level = window.level
        dropGuide.collectionBehavior = window.collectionBehavior
        dropGuide.animationBehavior = .none
        dropGuide.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.08))
                .strokeBorder(.white.opacity(0.55), lineWidth: 2.5)
                .accessibilityHidden(true))
        window.contentView = NSHostingView(rootView: ArtworkView(store: store) { [weak self] frame, phase in
            self?.updateDrag(frame, phase: phase)
        })
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !defaults.bool(forKey: "tileHidden") { window.orderFrontRegardless() }
    }

    var isVisible: Bool { window.isVisible }

    func toggle() {
        if isVisible {
            dragWidgets = nil
            dropGuide.orderOut(nil)
            window.orderOut(nil)
        } else {
            restorePosition()
            window.orderFrontRegardless()
        }
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
                let frame = CGRect(origin: CGPoint(x: x, y: y), size: window.frame.size)
                let widgets = widgetFrames()
                if NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }),
                   !widgets.contains(where: { frame.intersects($0) }) {
                    window.setFrameOrigin(frame.origin)
                } else {
                    place(frame, widgets: widgets)
                }
                return
            }
        }
        resetPosition()
    }

    @objc private func screenChanged() {
        if dragWidgets != nil {
            dragWidgets = widgetFrames()
            dropGuide.orderOut(nil)
        } else {
            restorePosition()
        }
    }

    private func updateDrag(_ frame: CGRect, phase: DragPhase) {
        guard window.isVisible else { return }
        let widgets = dragWidgets ?? widgetFrames()
        switch phase {
        case .moving:
            dragWidgets = widgets
            let target = TilePlacement.drop(frame, visibleScreens: NSScreen.screens.map(\.visibleFrame), widgets: widgets)
            window.setFrameOrigin(frame.origin)
            guard target.showsGuide else {
                dropGuide.orderOut(nil)
                return
            }
            // The slight outset keeps the outline visible even when the cover is centered over it.
            dropGuide.setFrame(target.frame.insetBy(dx: -4, dy: -4), display: true)
            if !dropGuide.isVisible { dropGuide.order(.below, relativeTo: window.windowNumber) }
        case .released:
            place(frame, widgets: widgets)
        }
    }

    private func place(_ frame: CGRect, widgets: [CGRect]? = nil) {
        dragWidgets = nil
        dropGuide.orderOut(nil)
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !screens.isEmpty else { return }
        let target = TilePlacement.fit(frame, visibleScreens: screens, widgets: widgets ?? widgetFrames())
        window.setFrameOrigin(target.origin)
        savePosition()
    }

    private func savePosition() {
        defaults.set(window.frame.origin.x, forKey: "tileX")
        defaults.set(window.frame.origin.y, forKey: "tileY")
    }
}
