import Foundation
import CoreGraphics

public enum TilePlacement {
    public static func fit(_ frame: CGRect, visibleScreens: [CGRect]) -> CGRect {
        guard let primary = visibleScreens.first else { return frame }
        let screen = visibleScreens.max { intersectionArea(frame, $0) < intersectionArea(frame, $1) } ?? primary
        guard frame.intersects(screen) else {
            return CGRect(x: primary.maxX - frame.width - 24, y: primary.maxY - frame.height - 24,
                width: frame.width, height: frame.height)
        }
        return CGRect(
            x: min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width)),
            y: min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY - frame.height)),
            width: frame.width, height: frame.height)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
