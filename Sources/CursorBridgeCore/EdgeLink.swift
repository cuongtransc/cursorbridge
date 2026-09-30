import CoreGraphics

public enum Edge: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right

    var runsVertically: Bool { self == .left || self == .right }
}

public struct EdgeRef: Codable, Hashable, Sendable {
    public var displayID: String
    public var edge: Edge

    public init(displayID: String, edge: Edge) {
        self.displayID = displayID
        self.edge = edge
    }
}

/// Joins two display edges end to end, whatever the layout geometry.
/// A position part-way along one edge maps to the same fraction of the other.
public struct EdgeLink: Codable, Hashable, Identifiable, Sendable {
    public var a: EdgeRef
    public var b: EdgeRef

    public init(_ a: EdgeRef, _ b: EdgeRef) {
        self.a = a
        self.b = b
    }

    public var id: String { "\(a.displayID).\(a.edge.rawValue)|\(b.displayID).\(b.edge.rawValue)" }

    public func involves(_ ref: EdgeRef) -> Bool { a == ref || b == ref }

    public func counterpart(of ref: EdgeRef) -> EdgeRef? {
        if a == ref { return b }
        if b == ref { return a }
        return nil
    }
}

extension CGRect {
    public func segment(along edge: Edge) -> Segment {
        switch edge {
        case .top: Segment(start: CGPoint(x: minX, y: minY), end: CGPoint(x: maxX, y: minY))
        case .bottom: Segment(start: CGPoint(x: minX, y: maxY), end: CGPoint(x: maxX, y: maxY))
        case .left: Segment(start: CGPoint(x: minX, y: minY), end: CGPoint(x: minX, y: maxY))
        case .right: Segment(start: CGPoint(x: maxX, y: minY), end: CGPoint(x: maxX, y: maxY))
        }
    }

    /// Where `point` sits along `edge`, from 0 at the top/left end to 1 at the bottom/right end.
    func fraction(of point: CGPoint, along edge: Edge) -> CGFloat {
        edge.runsVertically ? (point.y - minY) / height : (point.x - minX) / width
    }

    /// The cursor position just inside `edge`, `fraction` of the way along it.
    func cursorPoint(on edge: Edge, at fraction: CGFloat) -> CGPoint {
        let t = Swift.min(Swift.max(fraction, 0), 1)
        let point: CGPoint = switch edge {
        case .top: CGPoint(x: minX + t * width, y: minY)
        case .bottom: CGPoint(x: minX + t * width, y: maxY)
        case .left: CGPoint(x: minX, y: minY + t * height)
        case .right: CGPoint(x: maxX, y: minY + t * height)
        }
        return clamping(point)
    }
}
