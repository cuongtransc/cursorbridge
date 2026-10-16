import CoreGraphics

public struct Segment: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

public enum VirtualLayout {
    /// Roughly a 27" 1440p panel; used when no display reports a physical size.
    static let fallbackMillimetresPerPoint: CGFloat = 0.23

    public static func place(_ displays: [Display], origins: [String: CGPoint], mode: SizingMode) -> [PlacedDisplay] {
        let defaults = systemOrigins(for: displays, mode: mode)
        let scale = millimetresPerPoint(displays)
        return displays.map { display in
            let origin = origins[display.id] ?? defaults[display.id] ?? .zero
            let size = virtualSize(of: display, mode: mode, fallbackMillimetresPerPoint: scale)
            return PlacedDisplay(display: display, virtualFrame: CGRect(origin: origin, size: size))
        }
    }

    public static func systemOrigins(for displays: [Display], mode: SizingMode) -> [String: CGPoint] {
        let factor: CGFloat = mode == .logical ? 1 : millimetresPerPoint(displays)
        return Dictionary(
            displays.map { ($0.id, CGPoint(x: $0.frame.minX * factor, y: $0.frame.minY * factor)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func virtualSize(of display: Display, mode: SizingMode, fallbackMillimetresPerPoint: CGFloat) -> CGSize {
        switch mode {
        case .logical:
            return display.frame.size
        case .physical where display.hasPhysicalSize:
            return display.physicalSize
        case .physical:
            return CGSize(
                width: display.frame.width * fallbackMillimetresPerPoint,
                height: display.frame.height * fallbackMillimetresPerPoint
            )
        }
    }

    static func millimetresPerPoint(_ displays: [Display]) -> CGFloat {
        let ratios = displays.filter(\.hasPhysicalSize).map { $0.physicalSize.width / $0.frame.width }
        guard !ratios.isEmpty else { return fallbackMillimetresPerPoint }
        return ratios.reduce(0, +) / CGFloat(ratios.count)
    }

    public static func sharedEdges(of frames: [CGRect], tolerance: CGFloat = 0.5) -> [Segment] {
        var segments: [Segment] = []
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                if abs(a.maxX - b.minX) <= tolerance || abs(a.minX - b.maxX) <= tolerance {
                    let x = abs(a.maxX - b.minX) <= tolerance ? a.maxX : a.minX
                    let low = max(a.minY, b.minY), high = min(a.maxY, b.maxY)
                    if high - low > tolerance {
                        segments.append(Segment(start: CGPoint(x: x, y: low), end: CGPoint(x: x, y: high)))
                    }
                }
                if abs(a.maxY - b.minY) <= tolerance || abs(a.minY - b.maxY) <= tolerance {
                    let y = abs(a.maxY - b.minY) <= tolerance ? a.maxY : a.minY
                    let low = max(a.minX, b.minX), high = min(a.maxX, b.maxX)
                    if high - low > tolerance {
                        segments.append(Segment(start: CGPoint(x: low, y: y), end: CGPoint(x: high, y: y)))
                    }
                }
            }
        }
        return segments
    }

    /// The stretches of `edge` that look out onto another display, nearest first per stretch, with nothing
    /// nearer in between. This is what `CursorRouter`'s ray cast reaches from each point on the edge.
    public static func facingStretches(from index: Int, edge: Edge, in frames: [CGRect], tolerance: CGFloat = 0.5) -> [FacingStretch] {
        let a = frames[index]
        let candidates: [(index: Int, gap: CGFloat, span: Range<CGFloat>)] = frames.indices.compactMap { j in
            guard j != index else { return nil }
            let b = frames[j]
            switch edge {
            case .right where b.minX >= a.maxX - tolerance: return (j, b.minX - a.maxX, b.minY..<b.maxY)
            case .left where b.maxX <= a.minX + tolerance: return (j, a.minX - b.maxX, b.minY..<b.maxY)
            case .bottom where b.minY >= a.maxY - tolerance: return (j, b.minY - a.maxY, b.minX..<b.maxX)
            case .top where b.maxY <= a.minY + tolerance: return (j, a.minY - b.maxY, b.minX..<b.maxX)
            default: return nil
            }
        }

        var open = edge.runsVertically ? [a.minY..<a.maxY] : [a.minX..<a.maxX]
        var stretches: [FacingStretch] = []
        for candidate in candidates.sorted(by: { $0.gap < $1.gap }) {
            let covered = open.map { $0.clamped(to: candidate.span) }.filter { $0.upperBound - $0.lowerBound > tolerance }
            stretches += covered.map { FacingStretch(targetIndex: candidate.index, span: $0, gap: max(candidate.gap, 0)) }
            open = open.flatMap { $0.subtracting(candidate.span) }
        }
        return stretches
    }

    /// The display lying wholly beyond `edge` of frame `index` that is nearest to `point`, or to the
    /// frame itself when `point` is nil. Used where no display faces the edge straight on.
    public static func nearestBeyond(from index: Int, edge: Edge, at point: CGPoint? = nil, in frames: [CGRect], tolerance: CGFloat = 0.5) -> Int? {
        let a = frames[index]
        var best: (index: Int, distance: CGFloat)?
        for (j, b) in frames.enumerated() where j != index {
            let beyond = switch edge {
            case .right: b.minX >= a.maxX - tolerance
            case .left: b.maxX <= a.minX + tolerance
            case .bottom: b.minY >= a.maxY - tolerance
            case .top: b.maxY <= a.minY + tolerance
            }
            guard beyond else { continue }
            let distance = point.map { b.distance(to: $0) } ?? b.distance(to: a)
            if distance < (best?.distance ?? .infinity) {
                best = (j, distance)
            }
        }
        return best?.index
    }

    /// The stretches of every edge that face no display at all, each with the display the cursor
    /// reaches from there when it reaches sideways.
    public static func sidewaysReaches(in frames: [CGRect], tolerance: CGFloat = 0.5) -> [SidewaysReach] {
        var reaches: [SidewaysReach] = []
        for i in frames.indices {
            let a = frames[i]
            for edge in Edge.allCases {
                var open = edge.runsVertically ? [a.minY..<a.maxY] : [a.minX..<a.maxX]
                for stretch in facingStretches(from: i, edge: edge, in: frames, tolerance: tolerance) {
                    open = open.flatMap { $0.subtracting(stretch.span) }
                }
                for span in open where span.upperBound - span.lowerBound > tolerance {
                    let mid = (span.lowerBound + span.upperBound) / 2
                    let point = switch edge {
                    case .top: CGPoint(x: mid, y: a.minY)
                    case .bottom: CGPoint(x: mid, y: a.maxY)
                    case .left: CGPoint(x: a.minX, y: mid)
                    case .right: CGPoint(x: a.maxX, y: mid)
                    }
                    if let target = nearestBeyond(from: i, edge: edge, at: point, in: frames, tolerance: tolerance) {
                        reaches.append(SidewaysReach(sourceIndex: i, edge: edge, span: span, targetIndex: target))
                    }
                }
            }
        }
        return reaches
    }

    /// The empty regions the cursor jumps across when gap jumping is on.
    public static func gapBridges(of frames: [CGRect], tolerance: CGFloat = 0.5) -> [CGRect] {
        frames.indices.flatMap { i in
            let a = frames[i]
            let rightward = facingStretches(from: i, edge: .right, in: frames, tolerance: tolerance)
                .filter { $0.gap > tolerance }
                .map { CGRect(x: a.maxX, y: $0.span.lowerBound, width: $0.gap, height: $0.span.upperBound - $0.span.lowerBound) }
            let downward = facingStretches(from: i, edge: .bottom, in: frames, tolerance: tolerance)
                .filter { $0.gap > tolerance }
                .map { CGRect(x: $0.span.lowerBound, y: a.maxY, width: $0.span.upperBound - $0.span.lowerBound, height: $0.gap) }
            return rightward + downward
        }
    }
}

public struct FacingStretch: Equatable, Sendable {
    public let targetIndex: Int
    /// Along the edge: y for left/right edges, x for top/bottom.
    public let span: Range<CGFloat>
    public let gap: CGFloat
}

public struct SidewaysReach: Equatable, Sendable {
    public let sourceIndex: Int
    public let edge: Edge
    /// Along the edge: y for left/right edges, x for top/bottom.
    public let span: Range<CGFloat>
    public let targetIndex: Int
}

private extension Range where Bound == CGFloat {
    func subtracting(_ other: Range<CGFloat>) -> [Range<CGFloat>] {
        guard overlaps(other) else { return [self] }
        return [lowerBound..<Swift.max(lowerBound, other.lowerBound), Swift.min(upperBound, other.upperBound)..<upperBound]
            .filter { !$0.isEmpty }
    }
}

public enum LayoutSnapping {
    public static func snap(_ frame: CGRect, to others: [CGRect], threshold: CGFloat) -> CGRect {
        let dx = closestOffset(from: [frame.minX, frame.maxX], to: others.flatMap { [$0.minX, $0.maxX] }, within: threshold)
        let dy = closestOffset(from: [frame.minY, frame.maxY], to: others.flatMap { [$0.minY, $0.maxY] }, within: threshold)
        return frame.offsetBy(dx: dx, dy: dy)
    }

    public static func overlaps(_ frame: CGRect, _ others: [CGRect], tolerance: CGFloat = 0.5) -> Bool {
        others.contains { other in
            let intersection = frame.intersection(other)
            return !intersection.isNull && intersection.width > tolerance && intersection.height > tolerance
        }
    }

    private static func closestOffset(from edges: [CGFloat], to targets: [CGFloat], within threshold: CGFloat) -> CGFloat {
        var best = CGFloat.infinity
        for edge in edges {
            for target in targets {
                let offset = target - edge
                if abs(offset) <= threshold && abs(offset) < abs(best) {
                    best = offset
                }
            }
        }
        return best.isFinite ? best : 0
    }
}
