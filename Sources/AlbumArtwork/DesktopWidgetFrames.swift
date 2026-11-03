import AppKit
import ArtworkCore

enum DesktopWidgetFrames {
    /// WindowServer includes half the inter-widget gap on each edge, and measures
    /// y down from the primary display's top. Only inspect bounds, not window content.
    @MainActor static func current() -> [CGRect] {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .map(\.processIdentifier))
        let margin = (TilePlacement.pitch - TilePlacement.side) / 2
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int32,
                  layer > CGWindowLevelForKey(.desktopIconWindow), layer < CGWindowLevelForKey(.normalWindow),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  [frame.width, frame.height].allSatisfy({ $0 >= TilePlacement.pitch && $0.truncatingRemainder(dividingBy: TilePlacement.pitch) == 0 })
            else { return nil }
            return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
                .insetBy(dx: margin, dy: margin)
        }
    }
}
