import Foundation
import CoreGraphics

public enum TilePlacement {
    public static let side: CGFloat = 164
    private static let gap: CGFloat = 16
    public static let pitch = side + gap
    // Interaction tolerances for this tile, in screen points.
    private static let neighborReach = pitch / 3
    private static let edgeReach = gap * 2

    public struct Drop {
        public let frame: CGRect
        public let showsGuide: Bool
    }

    /// Native widget faces and visible screen bounds use AppKit screen coordinates.
    public static func drop(_ frame: CGRect, visibleScreens: [CGRect], widgets: [CGRect] = []) -> Drop {
        guard let primary = visibleScreens.first else { return Drop(frame: frame, showsGuide: false) }
        let best = visibleScreens.max { area(frame, $0) < area(frame, $1) } ?? primary
        let screen = area(frame, best) > 0 ? best : primary
        let origin = area(frame, best) > 0 ? frame.origin :
            CGPoint(x: primary.maxX - frame.width, y: primary.maxY - frame.height)
        let desired = CGRect(x: max(screen.minX, min(origin.x, screen.maxX - frame.width)),
                             y: max(screen.minY, min(origin.y, screen.maxY - frame.height)),
                             width: frame.width, height: frame.height)
        let local = widgets.filter { screen.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        let occupied = local.contains { area(desired, $0) > 0 }
        var nearest: CGRect?
        var bestDistance = CGFloat.infinity
        func consider(_ x: CGFloat, _ y: CGFloat, within reach: CGFloat) {
            let cell = CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
            let distance = hypot(x - desired.minX, y - desired.minY)
            guard distance < bestDistance, occupied || distance <= reach,
                  screen.contains(cell), !local.contains(where: { area(cell, $0) > 0 }) else { return }
            nearest = cell
            bestDistance = distance
        }

        // Each widget has its own alignment grid, including multi-cell widgets.
        for widget in local {
            let left = widget.minX - frame.width - gap, right = widget.maxX + gap
            let below = widget.minY - frame.height - gap, above = widget.maxY + gap
            for x in stride(from: left, through: right, by: pitch) {
                consider(x, below, within: neighborReach)
                consider(x, above, within: neighborReach)
            }
            for y in stride(from: widget.minY, to: widget.maxY, by: pitch) {
                consider(left, y, within: neighborReach)
                consider(right, y, within: neighborReach)
            }
        }

        let left = screen.minX + gap, right = screen.maxX - gap - frame.width
        let bottom = screen.minY + gap, top = screen.maxY - gap - frame.height
        // Step along the edge from the top or left. Include the opposite corner
        // explicitly since display dimensions are rarely an exact number of cells.
        let edgeRadius = hypot(edgeReach, pitch / 2)
        for x in [left, right] where occupied || abs(x - desired.minX) <= edgeReach {
            for y in stride(from: top, through: bottom, by: -pitch) {
                consider(x, y, within: edgeRadius)
            }
            consider(x, bottom, within: edgeRadius)
        }
        for y in [top, bottom] where occupied || abs(y - desired.minY) <= edgeReach {
            for x in stride(from: left, through: right, by: pitch) {
                consider(x, y, within: edgeRadius)
            }
            consider(right, y, within: edgeRadius)
        }

        return Drop(frame: nearest ?? desired, showsGuide: nearest != nil)
    }

    public static func fit(_ frame: CGRect, visibleScreens: [CGRect], widgets: [CGRect] = []) -> CGRect {
        drop(frame, visibleScreens: visibleScreens, widgets: widgets).frame
    }

    private static func area(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
