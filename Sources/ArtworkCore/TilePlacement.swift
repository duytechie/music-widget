import Foundation
import CoreGraphics

public enum TilePlacement {
    public static let side: CGFloat = 164
    private static let gap: CGFloat = 16
    public static let pitch = side + gap

    /// Native widget frames are the visible artwork, in AppKit screen coordinates.
    public static func fit(_ frame: CGRect, visibleScreens: [CGRect], widgets: [CGRect] = []) -> CGRect {
        guard let primary = visibleScreens.first else { return frame }
        let best = visibleScreens.max { intersectionArea(frame, $0) < intersectionArea(frame, $1) } ?? primary
        let screen = intersectionArea(frame, best) > 0 ? best : primary
        let target = intersectionArea(frame, best) > 0 ? frame : CGRect(
            x: primary.maxX - frame.width, y: primary.maxY - frame.height, width: frame.width, height: frame.height)

        let local = widgets.filter { screen.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        // A stable anchor keeps drops and restored positions on the same matrix.
        let anchor = local.sorted { $0.maxY == $1.maxY ? $0.minX < $1.minX : $0.maxY > $1.maxY }.first
        let left = anchor?.minX ?? screen.minX + gap
        let top = anchor?.maxY ?? screen.maxY - gap
        let columns = origins(anchor: left, low: screen.minX, high: screen.maxX - frame.width)
        let rows = origins(anchor: top - frame.height, low: screen.minY, high: screen.maxY - frame.height)

        var nearest: CGRect?
        var nearestFree: CGRect?
        func distance(_ cell: CGRect) -> CGFloat {
            hypot(cell.minX - target.minX, cell.minY - target.minY)
        }
        for x in columns {
            for y in rows {
                let cell = CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
                if nearest.map({ distance(cell) < distance($0) }) ?? true { nearest = cell }
                if (nearestFree.map({ distance(cell) < distance($0) }) ?? true),
                   !local.contains(where: { intersectionArea(cell, $0) > 0 }) {
                    nearestFree = cell
                }
            }
        }
        return nearestFree ?? nearest ?? frame
    }

    private static func origins(anchor: CGFloat, low: CGFloat, high: CGFloat) -> [CGFloat] {
        let first = anchor + ceil((low - anchor) / pitch) * pitch
        guard first <= high else { return [max(low, min(anchor, high))] }
        return Array(stride(from: first, through: high, by: pitch))
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
