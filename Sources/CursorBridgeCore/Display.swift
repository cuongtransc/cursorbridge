import CoreGraphics

public struct Display: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayID: CGDirectDisplayID
    public let name: String
    /// Global Quartz coordinates in points: origin at the top-left of the main display, y grows downwards.
    public let frame: CGRect
    /// Millimetres, matched to the current orientation. Zero when the display does not report it.
    public let physicalSize: CGSize

    public init(id: String, displayID: CGDirectDisplayID, name: String, frame: CGRect, physicalSize: CGSize) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.physicalSize = physicalSize
    }

    var hasPhysicalSize: Bool { physicalSize.width > 0 && physicalSize.height > 0 }
}

public enum SizingMode: String, Codable, CaseIterable, Sendable {
    case logical
    case physical
}

public struct PlacedDisplay: Identifiable, Equatable, Sendable {
    public let display: Display
    public let virtualFrame: CGRect

    public init(display: Display, virtualFrame: CGRect) {
        self.display = display
        self.virtualFrame = virtualFrame
    }

    public var id: String { display.id }

    private var scaleX: CGFloat { virtualFrame.width / display.frame.width }
    private var scaleY: CGFloat { virtualFrame.height / display.frame.height }

    public func toVirtual(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: virtualFrame.minX + (point.x - display.frame.minX) * scaleX,
            y: virtualFrame.minY + (point.y - display.frame.minY) * scaleY
        )
    }

    public func fromVirtual(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: display.frame.minX + (point.x - virtualFrame.minX) / scaleX,
            y: display.frame.minY + (point.y - virtualFrame.minY) / scaleY
        )
    }
}

extension CGRect {
    /// The cursor can sit on the last pixel row/column but never on maxX/maxY.
    func clamping(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: Swift.min(Swift.max(point.x, minX), maxX - 1),
            y: Swift.min(Swift.max(point.y, minY), maxY - 1)
        )
    }

    func distance(to point: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - point.x, 0, point.x - maxX)
        let dy = Swift.max(minY - point.y, 0, point.y - maxY)
        return hypot(dx, dy)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
