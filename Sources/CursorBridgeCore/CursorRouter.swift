import CoreGraphics

/// Decides where the cursor should be after a move, using the virtual layout instead of the macOS arrangement.
///
/// When the cursor leaves a display through an edge, the first rule that applies wins:
/// 1. an explicit wall on that edge blocks it;
/// 2. an explicit `EdgeLink` on that edge;
/// 3. a display touching that edge in the virtual layout;
/// 4. with `jumpsGaps`, the nearest display facing that edge across empty space.
/// Otherwise the edge is a wall, even when macOS has a neighbouring display there.
/// Walled and linked edges cannot be entered from the layout either, so each rule holds both ways.
public struct CursorRouter: Sendable {
    public enum Decision: Equatable, Sendable {
        case pass
        case warp(to: CGPoint)
    }

    /// A jump further than this from the source display cannot come from one mouse event,
    /// so something else (another app, a tablet) moved the cursor and we leave it alone.
    static let minimumForeignJump: CGFloat = 100
    /// Virtual units within which two edges count as touching.
    static let adjacencyTolerance: CGFloat = 0.5
    /// macOS holds a cursor against a wall exactly on the first row/column, or 1/64 pt short of the
    /// last. Anything further from the edge is still moving freely, possibly onto a native neighbour.
    static let pinnedTolerance: CGFloat = 0.25

    public let displays: [PlacedDisplay]
    public let jumpsGaps: Bool
    public let links: [EdgeLink]
    public let walls: Set<EdgeRef>
    /// Where no display faces an edge straight on, land on the nearest display lying beyond it.
    public let reachesSideways: Bool
    private let reservedEdges: Set<EdgeRef>

    public init(displays: [PlacedDisplay], jumpsGaps: Bool = false, links: [EdgeLink] = [], walls: Set<EdgeRef> = [], reachesSideways: Bool = false) {
        self.displays = displays
        self.jumpsGaps = jumpsGaps
        self.links = links
        self.walls = walls
        self.reachesSideways = reachesSideways
        self.reservedEdges = walls.union(links.flatMap { [$0.a, $0.b] })
    }

    /// - Parameters:
    ///   - previous: cursor location before this event.
    ///   - location: where macOS put the cursor for this event (already clamped or moved to a native neighbour).
    ///   - delta: the event's movement delta, used for direction when macOS clamped the cursor at an edge.
    public func route(from previous: CGPoint, to location: CGPoint, delta: CGVector) -> Decision {
        guard let source = displays.first(where: { $0.display.frame.contains(previous) }) else { return .pass }
        let frame = source.display.frame
        let leftSource = !frame.contains(location)

        if leftSource && frame.distance(to: location) > max(Self.minimumForeignJump, 4 * hypot(delta.dx, delta.dy)) {
            return .pass
        }

        guard let intended = leftSource ? location : Self.pushThroughEdge(of: frame, at: location, delta: delta) else {
            return .pass
        }

        guard let destination = crossing(from: source, toward: intended) else {
            return leftSource ? .warp(to: frame.clamping(location)) : .pass
        }
        return destination.distance(to: location) < 1 ? .pass : .warp(to: destination)
    }

    /// When macOS has no neighbour it pins the cursor to the edge; project it just past the edge in the
    /// direction of travel so the virtual layout can be consulted.
    static func pushThroughEdge(of frame: CGRect, at point: CGPoint, delta: CGVector) -> CGPoint? {
        var pushed = point
        if delta.dx < 0 && point.x < frame.minX + pinnedTolerance {
            pushed.x = point.x - max(1, -delta.dx)
        } else if delta.dx > 0 && point.x >= frame.maxX - pinnedTolerance {
            pushed.x = point.x + max(1, delta.dx)
        }
        if delta.dy < 0 && point.y < frame.minY + pinnedTolerance {
            pushed.y = point.y - max(1, -delta.dy)
        } else if delta.dy > 0 && point.y >= frame.maxY - pinnedTolerance {
            pushed.y = point.y + max(1, delta.dy)
        }
        return pushed == point ? nil : pushed
    }

    /// Each crossed edge is tried on its own, so a cursor sliding along a wall into a corner still
    /// crosses the edge that does lead somewhere.
    private func crossing(from source: PlacedDisplay, toward intended: CGPoint) -> CGPoint? {
        let frame = source.display.frame
        let clamped = frame.clamping(intended)
        var exits: [(Edge, CGPoint)] = []
        if intended.x < frame.minX {
            exits.append((.left, CGPoint(x: intended.x, y: clamped.y)))
        } else if intended.x >= frame.maxX {
            exits.append((.right, CGPoint(x: intended.x, y: clamped.y)))
        }
        if intended.y < frame.minY {
            exits.append((.top, CGPoint(x: clamped.x, y: intended.y)))
        } else if intended.y >= frame.maxY {
            exits.append((.bottom, CGPoint(x: clamped.x, y: intended.y)))
        }
        for (edge, point) in exits where !walls.contains(EdgeRef(displayID: source.id, edge: edge)) {
            if let destination = linkedDestination(from: source, through: edge, at: point)
                ?? facingDestination(from: source, through: edge, at: point) {
                return destination
            }
        }
        return nil
    }

    private func linkedDestination(from source: PlacedDisplay, through edge: Edge, at point: CGPoint) -> CGPoint? {
        let exit = EdgeRef(displayID: source.id, edge: edge)
        for link in links {
            guard let entry = link.counterpart(of: exit),
                  let target = displays.first(where: { $0.id == entry.displayID })
            else { continue }
            let fraction = source.display.frame.fraction(of: point, along: edge)
            return target.display.frame.cursorPoint(on: entry.edge, at: fraction)
        }
        return nil
    }

    /// Casts a ray out of `edge` in the virtual layout and lands on the nearest display it hits,
    /// carrying over however far the cursor overshot the edge.
    private func facingDestination(from source: PlacedDisplay, through edge: Edge, at point: CGPoint) -> CGPoint? {
        let v = source.toVirtual(point)
        let s = source.virtualFrame
        let tolerance = Self.adjacencyTolerance
        let maximumGap = jumpsGaps ? CGFloat.infinity : tolerance

        var best: (gap: CGFloat, target: PlacedDisplay, landing: CGPoint)?
        var facesAnything = false
        for target in displays where target.id != source.id {
            let t = target.virtualFrame
            let hit: (gap: CGFloat, landing: CGPoint)? = switch edge {
            case .right where t.minX >= s.maxX - tolerance && t.minY <= v.y && v.y < t.maxY:
                (t.minX - s.maxX, CGPoint(x: t.minX + (v.x - s.maxX), y: v.y))
            case .left where t.maxX <= s.minX + tolerance && t.minY <= v.y && v.y < t.maxY:
                (s.minX - t.maxX, CGPoint(x: t.maxX - (s.minX - v.x), y: v.y))
            case .bottom where t.minY >= s.maxY - tolerance && t.minX <= v.x && v.x < t.maxX:
                (t.minY - s.maxY, CGPoint(x: v.x, y: t.minY + (v.y - s.maxY)))
            case .top where t.maxY <= s.minY + tolerance && t.minX <= v.x && v.x < t.maxX:
                (s.minY - t.maxY, CGPoint(x: v.x, y: t.maxY - (s.minY - v.y)))
            default:
                nil
            }
            facesAnything = facesAnything || hit != nil
            if let hit, hit.gap <= maximumGap, hit.gap < (best?.gap ?? .infinity) {
                best = (hit.gap, target, hit.landing)
            }
        }
        // Only where nothing faces the edge at all: a gap left as a wall must stay one.
        if !facesAnything, reachesSideways,
           let index = displays.firstIndex(where: { $0.id == source.id }),
           let nearest = VirtualLayout.nearestBeyond(from: index, edge: edge, at: v, in: displays.map(\.virtualFrame)) {
            let target = displays[nearest]
            let t = target.virtualFrame
            let x = Swift.min(Swift.max(v.x, t.minX), t.maxX)
            let y = Swift.min(Swift.max(v.y, t.minY), t.maxY)
            let landing = switch edge {
            case .right: CGPoint(x: t.minX + (v.x - s.maxX), y: y)
            case .left: CGPoint(x: t.maxX - (s.minX - v.x), y: y)
            case .bottom: CGPoint(x: x, y: t.minY + (v.y - s.maxY))
            case .top: CGPoint(x: x, y: t.maxY - (s.minY - v.y))
            }
            best = (0, target, landing)
        }
        guard let best, !reservedEdges.contains(EdgeRef(displayID: best.target.id, edge: edge.opposite)) else { return nil }
        return best.target.display.frame.clamping(best.target.fromVirtual(best.landing))
    }
}
