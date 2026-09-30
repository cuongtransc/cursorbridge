import CoreGraphics

/// A cursor move the app has posted but macOS has not applied yet.
///
/// Until it lands, hardware events keep starting from the old position; routing them would bounce the
/// cursor back across the edge it just crossed.
public struct PendingMove: Equatable, Sendable {
    public static let lifetimeNanoseconds: UInt64 = 100_000_000
    static let minimumReach: CGFloat = 50

    public let target: CGPoint
    public let expiresAt: UInt64

    public init(target: CGPoint, postedAt now: UInt64) {
        self.target = target
        self.expiresAt = now + Self.lifetimeNanoseconds
    }

    /// An event is stale while the move is pending and the event is further from the target than one
    /// mouse event can travel.
    public func isStale(location: CGPoint, delta: CGVector, now: UInt64) -> Bool {
        now < expiresAt && location.distance(to: target) > max(Self.minimumReach, 4 * hypot(delta.dx, delta.dy))
    }
}
