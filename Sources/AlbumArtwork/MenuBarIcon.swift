import AppKit

/// The menu bar glyph: the app icon's record and note, drawn as a template
/// image so macOS tints it for light, dark and highlighted menu bars.
/// Geometry matches docs/menubar-icon.svg (24x24 grid, y down).
enum MenuBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let s = rect.width / 24
            NSGraphicsContext.current?.cgContext.scaleBy(x: s, y: s)
            NSColor.black.setFill()

            // Record with a centre hole (even-odd).
            let disc = NSBezierPath(ovalIn: NSRect(x: 3.8, y: 11.8, width: 10.4, height: 10.4))
            disc.append(NSBezierPath(ovalIn: NSRect(x: 7.2, y: 15.2, width: 3.6, height: 3.6)))
            disc.windingRule = .evenOdd
            disc.fill()

            // Stem.
            NSBezierPath(roundedRect: NSRect(x: 12.9, y: 3.5, width: 2.4, height: 14.5),
                         xRadius: 1.2, yRadius: 1.2).fill()

            // Flag (quadratic curves converted to cubics).
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: 14, y: 3.5))
            flag.quad(to: NSPoint(x: 20, y: 11.4), control: NSPoint(x: 21.2, y: 4.6))
            flag.quad(to: NSPoint(x: 14, y: 8.2), control: NSPoint(x: 17.6, y: 8.2))
            flag.close()
            flag.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Album Artwork"
        return image
    }
}

private extension NSBezierPath {
    func quad(to end: NSPoint, control: NSPoint) {
        let start = currentPoint
        curve(to: end,
              controlPoint1: NSPoint(x: start.x + 2.0 / 3.0 * (control.x - start.x),
                                     y: start.y + 2.0 / 3.0 * (control.y - start.y)),
              controlPoint2: NSPoint(x: end.x + 2.0 / 3.0 * (control.x - end.x),
                                     y: end.y + 2.0 / 3.0 * (control.y - end.y)))
    }
}
