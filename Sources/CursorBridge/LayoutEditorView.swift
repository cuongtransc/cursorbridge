import Combine
import CursorBridgeCore
import SwiftUI

enum LinkPicking: Equatable {
    case off
    case first
    case second(EdgeRef)

    var isActive: Bool { self != .off }
}

struct LayoutEditorView: View {
    @Bindable var model: AppModel
    @Binding var selection: String?
    @Binding var linkPicking: LinkPicking
    @State private var drag: DragState?
    @State private var hoveredEdge: EdgeRef?
    @State private var cursor: CGPoint?

    private static let canvasSpace = "layout-canvas"
    private static let snapDistance: CGFloat = 12
    private let cursorTimer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private struct DragState {
        let id: String
        let startFrame: CGRect
        let transform: CanvasTransform
        var frame: CGRect
        var overlaps = false
    }

    var body: some View {
        GeometryReader { proxy in
            let placed = model.placedDisplays
            let transform = drag?.transform ?? CanvasTransform(fitting: placed.map(\.virtualFrame), in: proxy.size)
            let frames = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0.id == drag?.id ? drag!.frame : $0.virtualFrame) })
            let ids = placed.map(\.id)
            let frameList = ids.compactMap { frames[$0] }

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { if !linkPicking.isActive { selection = nil } }

                if model.jumpsGaps {
                    ForEach(Array(bridges(ids: ids, frames: frameList).enumerated()), id: \.offset) { _, bridge in
                        GapBridge(rect: transform.toCanvas(bridge))
                    }
                }

                ForEach(placed) { display in
                    let rect = transform.toCanvas(frames[display.id]!)
                    DisplayTile(
                        number: model.number(of: display.display),
                        display: display.display,
                        virtualSize: frames[display.id]!.size,
                        mode: model.sizingMode,
                        state: tileState(for: display.id),
                        isSelected: selection == display.id,
                        isLinking: linkPicking.isActive
                    )
                    .frame(width: rect.width, height: rect.height)
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        guard linkPicking.isActive else { return }
                        if case .active(let location) = phase {
                            hoveredEdge = EdgeRef(displayID: display.id, edge: Self.nearestEdge(to: location, in: rect.size))
                        } else if hoveredEdge?.displayID == display.id {
                            hoveredEdge = nil
                        }
                    }
                    .onTapGesture(coordinateSpace: .local) { location in
                        if linkPicking.isActive {
                            pickEdge(EdgeRef(displayID: display.id, edge: Self.nearestEdge(to: location, in: rect.size)))
                        } else {
                            selection = display.id
                        }
                    }
                    // `.subviews` keeps the tap above working while dragging is switched off.
                    .gesture(dragGesture(for: display, among: placed, transform: transform), including: linkPicking.isActive ? .subviews : .all)
                    .position(x: rect.midX, y: rect.midY)
                }

                Group {
                    EdgeLines(segments: VirtualLayout.sharedEdges(of: frameList).map(transform.toCanvas), color: EdgeColors.touching)
                    ForEach(Array(model.sidewaysReaches.enumerated()), id: \.offset) { _, reach in
                        if let source = frames[reach.source.displayID], let target = frames[reach.targetEdge.displayID] {
                            SidewaysArrow(
                                along: transform.toCanvas(source.stretch(reach.span, along: reach.source.edge)),
                                into: transform.toCanvas(target.segment(along: reach.targetEdge.edge)),
                                outward: reach.source.edge.outward
                            )
                        }
                    }
                    ForEach(Array(model.walls), id: \.self) { wall in
                        if let frame = frames[wall.displayID] {
                            EdgeLines(segments: [transform.toCanvas(frame.segment(along: wall.edge))], color: EdgeColors.wall, width: 5)
                        }
                    }
                    ForEach(model.links) { link in
                        if let a = frames[link.a.displayID], let b = frames[link.b.displayID] {
                            LinkLine(
                                from: transform.toCanvas(a.segment(along: link.a.edge)),
                                to: transform.toCanvas(b.segment(along: link.b.edge))
                            )
                        }
                    }
                    ForEach(highlightedEdges, id: \.self) { ref in
                        if let frame = frames[ref.displayID] {
                            EdgeLines(segments: [transform.toCanvas(frame.segment(along: ref.edge))], color: .orange, width: 7)
                        }
                    }
                    if let cursor, drag == nil {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .position(transform.toCanvas(cursor))
                    }
                }
                .allowsHitTesting(false)
            }
            .coordinateSpace(.named(Self.canvasSpace))
        }
        .clipped()
        .onReceive(cursorTimer) { _ in cursor = model.virtualCursorLocation() }
        .onChange(of: linkPicking) { hoveredEdge = nil }
    }

    /// Gaps the cursor actually jumps: walls and links take their edges out of the layout.
    private func bridges(ids: [String], frames: [CGRect]) -> [CGRect] {
        let reserved = model.walls.union(model.links.flatMap { [$0.a, $0.b] })
        return frames.indices.flatMap { i -> [CGRect] in
            let a = frames[i]
            return [Edge.right, .bottom].flatMap { edge -> [CGRect] in
                guard !reserved.contains(EdgeRef(displayID: ids[i], edge: edge)) else { return [] }
                return VirtualLayout.facingStretches(from: i, edge: edge, in: frames)
                    .filter { $0.gap > 0.5 && !reserved.contains(EdgeRef(displayID: ids[$0.targetIndex], edge: edge.opposite)) }
                    .map { stretch in
                        let length = stretch.span.upperBound - stretch.span.lowerBound
                        return edge == .right
                            ? CGRect(x: a.maxX, y: stretch.span.lowerBound, width: stretch.gap, height: length)
                            : CGRect(x: stretch.span.lowerBound, y: a.maxY, width: length, height: stretch.gap)
                    }
            }
        }
    }

    private var highlightedEdges: [EdgeRef] {
        var edges: [EdgeRef] = []
        if case .second(let first) = linkPicking { edges.append(first) }
        if let hoveredEdge, !edges.contains(hoveredEdge) { edges.append(hoveredEdge) }
        return edges
    }

    private func pickEdge(_ ref: EdgeRef) {
        switch linkPicking {
        case .off:
            return
        case .first:
            linkPicking = .second(ref)
        case .second(let first) where first == ref:
            linkPicking = .first
        case .second(let first):
            model.link(first, ref)
            selection = first.displayID
            linkPicking = .off
        }
    }

    static func nearestEdge(to location: CGPoint, in size: CGSize) -> CursorBridgeCore.Edge {
        let distances: [(CursorBridgeCore.Edge, CGFloat)] = [
            (.left, location.x),
            (.right, size.width - location.x),
            (.top, location.y),
            (.bottom, size.height - location.y),
        ]
        return distances.min { $0.1 < $1.1 }!.0
    }

    private func tileState(for id: String) -> DisplayTile.State {
        guard let drag, drag.id == id else { return .idle }
        return drag.overlaps ? .blocked : .dragging
    }

    private func dragGesture(for display: PlacedDisplay, among placed: [PlacedDisplay], transform: CanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                var state = drag ?? DragState(
                    id: display.id,
                    startFrame: display.virtualFrame,
                    transform: transform,
                    frame: display.virtualFrame
                )
                let others = placed.filter { $0.id != display.id }.map(\.virtualFrame)
                let moved = state.startFrame.offsetBy(
                    dx: value.translation.width / state.transform.scale,
                    dy: value.translation.height / state.transform.scale
                )
                state.frame = LayoutSnapping.snap(moved, to: others, threshold: Self.snapDistance / state.transform.scale)
                state.overlaps = LayoutSnapping.overlaps(state.frame, others)
                drag = state
                selection = display.id
            }
            .onEnded { _ in
                if let drag, !drag.overlaps {
                    model.moveDisplay(drag.id, to: drag.frame.origin)
                }
                drag = nil
            }
    }
}

private typealias Edge = CursorBridgeCore.Edge

struct CanvasTransform {
    let origin: CGPoint
    let scale: CGFloat

    init(fitting frames: [CGRect], in size: CGSize, padding: CGFloat = 48) {
        let bounds = frames.reduce(CGRect.null) { $0.union($1) }
        let available = CGSize(width: size.width - 2 * padding, height: size.height - 2 * padding)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0, available.width > 0, available.height > 0 else {
            origin = .zero
            scale = 1
            return
        }
        scale = min(available.width / bounds.width, available.height / bounds.height)
        origin = CGPoint(x: bounds.midX - size.width / 2 / scale, y: bounds.midY - size.height / 2 / scale)
    }

    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) * scale, y: (point.y - origin.y) * scale)
    }

    func toCanvas(_ rect: CGRect) -> CGRect {
        CGRect(origin: toCanvas(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    func toCanvas(_ segment: Segment) -> Segment {
        Segment(start: toCanvas(segment.start), end: toCanvas(segment.end))
    }
}

private extension Segment {
    var midpoint: CGPoint { CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }
}

private struct EdgeLines: View {
    let segments: [Segment]
    let color: Color
    var width: CGFloat = 4
    var dash: [CGFloat] = []

    var body: some View {
        Path { path in
            for segment in segments {
                path.move(to: segment.start)
                path.addLine(to: segment.end)
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: dash.isEmpty ? .round : .butt, dash: dash))
    }
}

private struct LinkLine: View {
    let from: Segment
    let to: Segment

    var body: some View {
        ZStack {
            EdgeLines(segments: [from, to], color: .orange, width: 5)
            Path { path in
                path.move(to: from.midpoint)
                path.addLine(to: to.midpoint)
            }
            .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
            Circle().fill(.orange).frame(width: 9, height: 9).position(from.midpoint)
            Circle().fill(.orange).frame(width: 9, height: 9).position(to.midpoint)
        }
    }
}

private extension CGRect {
    /// The part of `edge` that `span` covers (y for left/right edges, x for top/bottom).
    func stretch(_ span: Range<CGFloat>, along edge: CursorBridgeCore.Edge) -> Segment {
        switch edge {
        case .top: Segment(start: CGPoint(x: span.lowerBound, y: minY), end: CGPoint(x: span.upperBound, y: minY))
        case .bottom: Segment(start: CGPoint(x: span.lowerBound, y: maxY), end: CGPoint(x: span.upperBound, y: maxY))
        case .left: Segment(start: CGPoint(x: minX, y: span.lowerBound), end: CGPoint(x: minX, y: span.upperBound))
        case .right: Segment(start: CGPoint(x: maxX, y: span.lowerBound), end: CGPoint(x: maxX, y: span.upperBound))
        }
    }
}

/// A dashed stretch that faces nothing, with an arrow to the nearest point of the display it reaches.
private struct SidewaysArrow: View {
    let along: Segment
    let into: Segment
    /// Unit vector pointing out of the source edge, which is also into the target display.
    let outward: CGVector

    var body: some View {
        let from = along.midpoint
        let entry = into.nearestPoint(to: from)
        // Bend out of the edge and end just inside the target, so the arrow never lies along the edges.
        let to = CGPoint(x: entry.x + outward.dx * 14, y: entry.y + outward.dy * 14)
        let control = CGPoint(x: from.x + outward.dx * 40, y: from.y + outward.dy * 40)
        let angle = atan2(to.y - control.y, to.x - control.x)
        ZStack {
            EdgeLines(segments: [along], color: EdgeColors.sideways, width: 4, dash: [7, 5])
            Path { path in
                path.move(to: from)
                path.addQuadCurve(to: to, control: control)
                for side in [-1.0, 1.0] {
                    path.move(to: to)
                    path.addLine(to: CGPoint(x: to.x - 9 * cos(angle + side * 0.5), y: to.y - 9 * sin(angle + side * 0.5)))
                }
            }
            .stroke(EdgeColors.sideways, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

private extension CursorBridgeCore.Edge {
    var outward: CGVector {
        switch self {
        case .top: CGVector(dx: 0, dy: -1)
        case .bottom: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
    }
}

private extension Segment {
    func nearestPoint(to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, min(start.x, end.x)), max(start.x, end.x)),
            y: min(max(point.y, min(start.y, end.y)), max(start.y, end.y))
        )
    }
}

private struct GapBridge: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.green.opacity(0.3))
            .overlay(Rectangle().strokeBorder(Color.green.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .frame(width: max(rect.width, 6), height: max(rect.height, 6))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

private struct DisplayTile: View {
    enum State { case idle, dragging, blocked }

    let number: Int
    let display: Display
    let virtualSize: CGSize
    let mode: SizingMode
    let state: State
    let isSelected: Bool
    let isLinking: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(stroke, lineWidth: isSelected || state != .idle ? 3 : 1))
            .overlay(alignment: .top) {
                if display.displayID == CGMainDisplayID() {
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(height: 5)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                }
            }
            .overlay {
                VStack(spacing: 2) {
                    Text("\(number)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(display.name)
                        .font(.caption.weight(.semibold))
                    Text(sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .padding(6)
            }
            .contentShape(shape)
            .help(isLinking ? "Click near an edge to pick it" : "Click to select, drag to move")
    }

    private var sizeLabel: String {
        switch mode {
        case .logical:
            "\(Int(display.frame.width)) × \(Int(display.frame.height)) pt"
        case .physical:
            "\(Int(virtualSize.width.rounded())) × \(Int(virtualSize.height.rounded())) mm"
        }
    }

    private var fill: Color {
        switch state {
        case .idle: Color.accentColor.opacity(isSelected ? 0.4 : 0.25)
        case .dragging: Color.accentColor.opacity(0.45)
        case .blocked: Color.red.opacity(0.35)
        }
    }

    private var stroke: Color {
        state == .blocked ? .red : Color.accentColor
    }
}
