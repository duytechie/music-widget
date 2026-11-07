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
        .accessibilityLabel(store.track.map { "\($0.album), \($0.artist)" } ?? "Album artwork")
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
    private var screenRestoreTask: Task<Void, Never>?
    private let defaults: UserDefaults
    struct Display {
        let id: String
        let visibleFrame: CGRect
    }
    private let displays: @MainActor () -> [Display]

    static func currentDisplays() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
            else { return nil }
            return Display(id: CFUUIDCreateString(nil, uuid) as String, visibleFrame: screen.visibleFrame)
        }
    }

    init(store: ArtworkStore, defaults: UserDefaults = .standard,
         widgetFrames: @escaping @MainActor () -> [CGRect] = { DesktopWidgetFrames.current() },
         displays: @escaping @MainActor () -> [Display] = { DesktopTile.currentDisplays() }) {
        self.widgetFrames = widgetFrames
        self.defaults = defaults
        self.displays = displays
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
        screenRestoreTask?.cancel()
        guard let screen = displays().first else { return }
        let visible = screen.visibleFrame
        place(CGRect(x: visible.maxX - Self.side, y: visible.maxY - Self.side, width: Self.side, height: Self.side))
    }

    private func restorePosition() {
        let screens = displays()
        guard let primary = screens.first else { return }
        let savedDisplay = defaults.string(forKey: "tileDisplayID")
        // Existing placements predate the display-role preference: migrate them to
        // the main desktop. Explicit drops on secondary displays remain pinned.
        let followsPrimary = defaults.object(forKey: "tileFollowsPrimary") == nil || defaults.bool(forKey: "tileFollowsPrimary")
        let matching = followsPrimary ? primary : screens.first { $0.id == savedDisplay }
        var frame: CGRect?
        if savedDisplay != nil,
           defaults.object(forKey: "tileRight") != nil, defaults.object(forKey: "tileTop") != nil {
            let right = defaults.double(forKey: "tileRight")
            let top = defaults.double(forKey: "tileTop")
            if right.isFinite && top.isFinite {
                let visible = (matching ?? primary).visibleFrame
                let horizontal = defaults.string(forKey: "tileHorizontalEdge")
                let vertical = defaults.string(forKey: "tileVerticalEdge")
                let dx = defaults.double(forKey: "tileHorizontalInset")
                let dy = defaults.double(forKey: "tileVerticalInset")
                frame = CGRect(x: horizontal == "left" && dx.isFinite ? visible.minX + dx :
                                horizontal == "right" && dx.isFinite ? visible.maxX - Self.side - dx : visible.maxX - Self.side - right,
                               y: vertical == "bottom" && dy.isFinite ? visible.minY + dy :
                                vertical == "top" && dy.isFinite ? visible.maxY - Self.side - dy : visible.maxY - Self.side - top,
                               width: Self.side, height: Self.side)
            }
        }
        if frame == nil, defaults.object(forKey: "tileX") != nil, defaults.object(forKey: "tileY") != nil {
            let x = defaults.double(forKey: "tileX"), y = defaults.double(forKey: "tileY")
            if x.isFinite && y.isFinite {
                frame = CGRect(x: x, y: y, width: Self.side, height: Self.side)
            }
        }
        guard let frame else { resetPosition(); return }
        // Constrain to the saved display even if its origin or resolution changed.
        let visible = savedDisplay == nil ? screens.map(\.visibleFrame) : [(matching ?? primary).visibleFrame]
        let widgets = widgetFrames()
        let target: CGRect
        if visible.contains(where: { $0.contains(frame) }), !widgets.contains(where: { frame.intersects($0) }) {
            target = frame
        } else {
            target = TilePlacement.fit(frame, visibleScreens: visible, widgets: widgets)
        }
        window.setFrameOrigin(target.origin)
        // A temporary fallback must not overwrite the preferred display's position.
        // Migrate legacy absolute coordinates once; only an explicit drop/reset changes it afterward.
        if savedDisplay == nil || (defaults.string(forKey: "tileVerticalEdge") == nil && matching?.id == savedDisplay) {
            savePosition()
        }
    }

    @objc private func screenChanged() {
        screenRestoreTask?.cancel()
        dragWidgets = nil
        dropGuide.orderOut(nil)
        restorePosition()
        // AppKit can relocate windows and Notification Center can reflow widgets
        // after the initial notification. Re-read geometry without saving fallback
        // positions. A new display event or user drag cancels these retries.
        screenRestoreTask = Task { @MainActor [weak self] in
            for delay in [250_000_000, 750_000_000, 1_000_000_000] {
                do { try await Task.sleep(nanoseconds: UInt64(delay)) } catch { return }
                guard let self else { return }
                self.restorePosition()
            }
        }
    }

    private func updateDrag(_ frame: CGRect, phase: DragPhase) {
        guard window.isVisible else { return }
        screenRestoreTask?.cancel()
        let widgets = dragWidgets ?? widgetFrames()
        switch phase {
        case .moving:
            dragWidgets = widgets
            let target = TilePlacement.drop(frame, visibleScreens: displays().map(\.visibleFrame), widgets: widgets)
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
        let screens = displays().map(\.visibleFrame)
        guard !screens.isEmpty else { return }
        let target = TilePlacement.fit(frame, visibleScreens: screens, widgets: widgets ?? widgetFrames())
        window.setFrameOrigin(target.origin)
        savePosition()
    }

    private func savePosition() {
        defaults.set(window.frame.origin.x, forKey: "tileX")
        defaults.set(window.frame.origin.y, forKey: "tileY")
        let frame = window.frame
        let screen = displays().max { lhs, rhs in
            func area(_ visible: CGRect) -> CGFloat {
                let intersection = frame.intersection(visible)
                return intersection.isNull ? 0 : intersection.width * intersection.height
            }
            return area(lhs.visibleFrame) < area(rhs.visibleFrame)
        }
        guard let screen else { return }
        defaults.set(screen.id, forKey: "tileDisplayID")
        defaults.set(screen.id == displays().first?.id, forKey: "tileFollowsPrimary")
        let visible = screen.visibleFrame
        let left = frame.minX - visible.minX, right = visible.maxX - frame.maxX
        let bottom = frame.minY - visible.minY, top = visible.maxY - frame.maxY
        defaults.set(left <= right ? "left" : "right", forKey: "tileHorizontalEdge")
        defaults.set(min(left, right), forKey: "tileHorizontalInset")
        defaults.set(bottom <= top ? "bottom" : "top", forKey: "tileVerticalEdge")
        defaults.set(min(bottom, top), forKey: "tileVerticalInset")
        defaults.set(screen.visibleFrame.maxX - frame.maxX, forKey: "tileRight")
        defaults.set(screen.visibleFrame.maxY - frame.maxY, forKey: "tileTop")
    }
}
