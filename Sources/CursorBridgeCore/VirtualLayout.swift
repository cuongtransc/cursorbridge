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

    /// The empty regions the cursor jumps across when gap jumping is on — one rectangle per stretch of
    /// edge that faces another display with nothing nearer in between. Mirrors `CursorRouter`'s ray cast.
    public static func gapBridges(of frames: [CGRect], tolerance: CGFloat = 0.5) -> [CGRect] {
        var bridges: [CGRect] = []
        for a in frames {
            let rightward = frames
                .filter { $0 != a && $0.minX >= a.maxX - tolerance }
                .sorted { $0.minX < $1.minX }
            var open = [a.minY..<a.maxY]
            for b in rightward {
                let covered = open.map { $0.clamped(to: b.minY..<b.maxY) }.filter { !$0.isEmpty }
                if b.minX - a.maxX > tolerance {
                    bridges += covered.map { CGRect(x: a.maxX, y: $0.lowerBound, width: b.minX - a.maxX, height: $0.upperBound - $0.lowerBound) }
                }
                open = open.flatMap { $0.subtracting(b.minY..<b.maxY) }
            }

            let downward = frames
                .filter { $0 != a && $0.minY >= a.maxY - tolerance }
                .sorted { $0.minY < $1.minY }
            open = [a.minX..<a.maxX]
            for b in downward {
                let covered = open.map { $0.clamped(to: b.minX..<b.maxX) }.filter { !$0.isEmpty }
                if b.minY - a.maxY > tolerance {
                    bridges += covered.map { CGRect(x: $0.lowerBound, y: a.maxY, width: $0.upperBound - $0.lowerBound, height: b.minY - a.maxY) }
                }
                open = open.flatMap { $0.subtracting(b.minX..<b.maxX) }
            }
        }
        return bridges.filter { $0.width > tolerance && $0.height > tolerance }
    }
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
