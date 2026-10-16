import CoreGraphics
import Testing
@testable import CursorBridgeCore

private func display(_ id: String, _ frame: CGRect, mm: CGSize = .zero) -> Display {
    Display(id: id, displayID: 0, name: id, frame: frame, physicalSize: mm)
}

/// macOS arrangement used throughout: A (1000x800) with B (1000x800) to its right.
/// Where macOS holds a cursor pushed against the right or bottom edge of a 1000 x 800 display.
private let pinnedRight: CGFloat = 1000 - 1.0 / 64
private let pinnedBottom: CGFloat = 800 - 1.0 / 64

private let a = display("A", CGRect(x: 0, y: 0, width: 1000, height: 800))
private let b = display("B", CGRect(x: 1000, y: 0, width: 1000, height: 800))

@Suite struct CursorRouterTests {
    @Test func matchingLayoutLetsMacOSHandleTheCrossing() {
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: [:], mode: .logical))
        let decision = router.route(from: CGPoint(x: 998, y: 400), to: CGPoint(x: 1003, y: 400), delta: CGVector(dx: 5, dy: 0))
        #expect(decision == .pass)
    }

    @Test func movesWithinADisplayAreUntouched() {
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: [:], mode: .logical))
        #expect(router.route(from: CGPoint(x: 500, y: 400), to: CGPoint(x: 510, y: 410), delta: CGVector(dx: 10, dy: 10)) == .pass)
    }

    @Test func nativeNeighbourBecomesAWallWhenNotAdjacentVirtually() {
        let stacked = ["A": CGPoint(x: 0, y: 0), "B": CGPoint(x: 0, y: 800)]
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: stacked, mode: .logical))
        let decision = router.route(from: CGPoint(x: 998, y: 400), to: CGPoint(x: 1003, y: 400), delta: CGVector(dx: 5, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: 999, y: 400)))
    }

    @Test func virtualNeighbourIsReachedThroughASystemWall() {
        let stacked = ["A": CGPoint(x: 0, y: 0), "B": CGPoint(x: 0, y: 800)]
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: stacked, mode: .logical))
        let decision = router.route(from: CGPoint(x: 300, y: 797), to: CGPoint(x: 300, y: pinnedBottom), delta: CGVector(dx: 0, dy: 4))
        #expect(decision == .warp(to: CGPoint(x: 1300, y: 3.984375)))
    }

    @Test func swappedSidesSendTheCursorAcrossTheWholeDesk() {
        let swapped = ["A": CGPoint(x: 1000, y: 0), "B": CGPoint(x: 0, y: 0)]
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: swapped, mode: .logical))
        let decision = router.route(from: CGPoint(x: 1, y: 250), to: CGPoint(x: 0, y: 250), delta: CGVector(dx: -3, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: 1997, y: 250)))
    }

    @Test func physicalSizingPreservesTheRealWorldHeight() {
        let retina = display("A", CGRect(x: 0, y: 0, width: 1000, height: 800), mm: CGSize(width: 300, height: 240))
        let large = display("B", CGRect(x: 1000, y: 0, width: 1000, height: 800), mm: CGSize(width: 600, height: 480))
        let origins = ["A": CGPoint(x: 0, y: 120), "B": CGPoint(x: 300, y: 0)]
        let router = CursorRouter(displays: VirtualLayout.place([retina, large], origins: origins, mode: .physical))
        let decision = router.route(from: CGPoint(x: 999, y: 0), to: CGPoint(x: pinnedRight, y: 0), delta: CGVector(dx: 2, dy: 0))
        guard case .warp(let target) = decision else { Issue.record("expected warp, got \(decision)"); return }
        #expect(target.y == 200)
        #expect(target.x > 1000 && target.x < 1010)
    }

    @Test func slidingIntoACornerStillCrossesTheOpenEdge() {
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: [:], mode: .logical))
        let decision = router.route(from: CGPoint(x: 999, y: 799), to: CGPoint(x: pinnedRight, y: pinnedBottom), delta: CGVector(dx: 3, dy: 3))
        #expect(decision == .warp(to: CGPoint(x: 1002.984375, y: 799)))
    }

    @Test func foreignJumpsAreIgnored() {
        let stacked = ["A": CGPoint(x: 0, y: 0), "B": CGPoint(x: 0, y: 800)]
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: stacked, mode: .logical))
        #expect(router.route(from: CGPoint(x: 500, y: 400), to: CGPoint(x: 1500, y: 400), delta: CGVector(dx: 1, dy: 0)) == .pass)
    }

    @Test func wallWithoutNeighbourStaysPut() {
        let router = CursorRouter(displays: VirtualLayout.place([a, b], origins: [:], mode: .logical))
        #expect(router.route(from: CGPoint(x: 0, y: 400), to: CGPoint(x: 0, y: 400), delta: CGVector(dx: -5, dy: 0)) == .pass)
    }
}

@Suite struct LayoutTests {
    @Test func snapsToNearbyEdge() {
        let snapped = LayoutSnapping.snap(CGRect(x: 1006, y: -4, width: 100, height: 100), to: [CGRect(x: 0, y: 0, width: 1000, height: 800)], threshold: 10)
        #expect(snapped.origin == CGPoint(x: 1000, y: 0))
    }

    @Test func ignoresDistantEdges() {
        let frame = CGRect(x: 1050, y: 300, width: 100, height: 100)
        #expect(LayoutSnapping.snap(frame, to: [CGRect(x: 0, y: 0, width: 1000, height: 800)], threshold: 10) == frame)
    }

    @Test func touchingIsNotOverlapping() {
        let base = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(!LayoutSnapping.overlaps(CGRect(x: 1000, y: 0, width: 10, height: 10), [base]))
        #expect(LayoutSnapping.overlaps(CGRect(x: 990, y: 0, width: 20, height: 10), [base]))
    }

    @Test func sharedEdgesOnlyCoverTheOverlap() {
        let edges = VirtualLayout.sharedEdges(of: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 400, width: 500, height: 800),
            CGRect(x: 0, y: 2000, width: 10, height: 10),
        ])
        #expect(edges == [Segment(start: CGPoint(x: 1000, y: 400), end: CGPoint(x: 1000, y: 800))])
    }

    @Test func alignedButSeparateFramesShareNothing() {
        let edges = VirtualLayout.sharedEdges(of: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 0, y: 900, width: 1000, height: 800),
        ])
        #expect(edges.isEmpty)
    }
}

/// A 2x2 grid whose top-right display is shorter than the top-left one, leaving a 200 pt gap
/// between it and the display below:
///
///     ┌──────┐┌──────┐
///     │  TL  ││  TR  │
///     │      │└──────┘   ← gap
///     └──────┘┌──────┐
///     ┌──────┐│  BR  │
///     │  BL  ││      │
private let tl = display("TL", CGRect(x: 0, y: 0, width: 1000, height: 1000))
private let tr = display("TR", CGRect(x: 1000, y: 0, width: 1000, height: 800))
private let bl = display("BL", CGRect(x: 0, y: 1000, width: 1000, height: 800))
private let br = display("BR", CGRect(x: 1000, y: 1000, width: 1000, height: 800))
private let grid = VirtualLayout.place([tl, tr, bl, br], origins: [:], mode: .logical)

@Suite struct GapTests {
    @Test func gapIsAWallByDefault() {
        let router = CursorRouter(displays: grid)
        #expect(router.route(from: CGPoint(x: 1500, y: 798), to: CGPoint(x: 1500, y: pinnedBottom), delta: CGVector(dx: 0, dy: 5)) == .pass)
    }

    @Test func jumpsDownAcrossTheGap() {
        let router = CursorRouter(displays: grid, jumpsGaps: true)
        let decision = router.route(from: CGPoint(x: 1500, y: 798), to: CGPoint(x: 1500, y: pinnedBottom), delta: CGVector(dx: 0, dy: 5))
        #expect(decision == .warp(to: CGPoint(x: 1500, y: 1004.984375)))
    }

    @Test func jumpsBackUpAcrossTheGap() {
        let router = CursorRouter(displays: grid, jumpsGaps: true)
        let decision = router.route(from: CGPoint(x: 1500, y: 1001), to: CGPoint(x: 1500, y: 1000), delta: CGVector(dx: 0, dy: -3))
        #expect(decision == .warp(to: CGPoint(x: 1500, y: 797)))
    }

    @Test func nearestFacingDisplayWins() {
        let far = display("FAR", CGRect(x: 1000, y: 3000, width: 1000, height: 800))
        let router = CursorRouter(displays: VirtualLayout.place([tl, tr, br, far], origins: [:], mode: .logical), jumpsGaps: true)
        guard case .warp(let target) = router.route(from: CGPoint(x: 1500, y: 798), to: CGPoint(x: 1500, y: pinnedBottom), delta: CGVector(dx: 0, dy: 5))
        else { Issue.record("expected warp"); return }
        #expect(br.frame.contains(target))
    }

    @Test func touchingNeighboursStillPassThrough() {
        let router = CursorRouter(displays: grid, jumpsGaps: true)
        #expect(router.route(from: CGPoint(x: 998, y: 500), to: CGPoint(x: 1003, y: 500), delta: CGVector(dx: 5, dy: 0)) == .pass)
    }
}

@Suite struct EdgeLinkTests {
    private let link = EdgeLink(EdgeRef(displayID: "TR", edge: .bottom), EdgeRef(displayID: "BL", edge: .top))

    @Test func linkMapsProportionallyAlongTheEdge() {
        let router = CursorRouter(displays: grid, links: [link])
        let decision = router.route(from: CGPoint(x: 1250, y: 798), to: CGPoint(x: 1250, y: pinnedBottom), delta: CGVector(dx: 0, dy: 5))
        #expect(decision == .warp(to: CGPoint(x: 250, y: 1000)))
    }

    @Test func linksWorkInBothDirections() {
        let router = CursorRouter(displays: grid, links: [link])
        let decision = router.route(from: CGPoint(x: 750, y: 1001), to: CGPoint(x: 750, y: 1000), delta: CGVector(dx: 0, dy: -2))
        #expect(decision == .warp(to: CGPoint(x: 1750, y: 799)))
    }

    @Test func linkOverridesATouchingNeighbour() {
        let rightToBottom = EdgeLink(EdgeRef(displayID: "TL", edge: .right), EdgeRef(displayID: "BR", edge: .left))
        let router = CursorRouter(displays: grid, links: [rightToBottom])
        let decision = router.route(from: CGPoint(x: 998, y: 500), to: CGPoint(x: 1003, y: 500), delta: CGVector(dx: 5, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: 1000, y: 1400)))
    }

    @Test func linkToADisconnectedDisplayFallsBackToTheLayout() {
        let stale = EdgeLink(EdgeRef(displayID: "TR", edge: .bottom), EdgeRef(displayID: "GONE", edge: .top))
        let router = CursorRouter(displays: grid, jumpsGaps: true, links: [stale])
        let decision = router.route(from: CGPoint(x: 1500, y: 798), to: CGPoint(x: 1500, y: pinnedBottom), delta: CGVector(dx: 0, dy: 5))
        #expect(decision == .warp(to: CGPoint(x: 1500, y: 1004.984375)))
    }
}

@Suite struct GapBridgeTests {
    @Test func bridgeCoversOnlyTheFacingStretch() {
        let bridges = VirtualLayout.gapBridges(of: grid.map(\.virtualFrame))
        #expect(bridges == [CGRect(x: 1000, y: 800, width: 1000, height: 200)])
    }

    @Test func nearerDisplayShadowsAFartherOne() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 200, y: 0, width: 100, height: 50),
            CGRect(x: 400, y: 0, width: 100, height: 100),
        ]
        let bridges = VirtualLayout.gapBridges(of: frames)
        #expect(bridges.contains(CGRect(x: 100, y: 0, width: 100, height: 50)))
        #expect(bridges.contains(CGRect(x: 100, y: 50, width: 300, height: 50)))
        #expect(bridges.contains(CGRect(x: 300, y: 0, width: 100, height: 50)))
        #expect(bridges.count == 3)
    }
}

/// The five-display desk this app was built for, as macOS reports it. Display 1's right edge (x = 0)
/// faces display 4's left edge (x = 36) across a 36 pt gap for y in -1060..<0.
@Suite struct DeskTests {
    private let one = display("1", CGRect(x: -3008, y: -1060, width: 3008, height: 1692))
    private let two = display("2", CGRect(x: -2972, y: -2752, width: 3008, height: 1692))
    private let laptop = display("3", CGRect(x: 0, y: 0, width: 1728, height: 1117))
    private let four = display("4", CGRect(x: 36, y: -3008, width: 1692, height: 3008))
    private let five = display("5", CGRect(x: 1728, y: -2358, width: 1692, height: 3008))

    private var router: CursorRouter {
        CursorRouter(displays: VirtualLayout.place([one, two, laptop, four, five], origins: [:], mode: .logical), jumpsGaps: true)
    }

    @Test func crossesTheGapFromOneToFour() {
        let decision = router.route(from: CGPoint(x: -1.5, y: -500), to: CGPoint(x: -1.0 / 64, y: -500), delta: CGVector(dx: 4, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: 39.984375, y: -500)))
    }

    @Test func crossesTheGapFromFourToOne() {
        let decision = router.route(from: CGPoint(x: 37, y: -500), to: CGPoint(x: 36, y: -500), delta: CGVector(dx: -4, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: -4, y: -500)))
    }

    @Test func approachingANativeEdgeIsNotMistakenForBeingPinned() {
        #expect(router.route(from: CGPoint(x: -1218.6875, y: -1062), to: CGPoint(x: -1218.6875, y: -1060.375), delta: CGVector(dx: 0, dy: 2)) == .pass)
        #expect(router.route(from: CGPoint(x: -1216.625, y: -1058), to: CGPoint(x: -1216.625, y: -1059.6875), delta: CGVector(dx: 0, dy: -1)) == .pass)
    }

    @Test func nativeEdgesAreLeftToMacOS() {
        #expect(router.route(from: CGPoint(x: -2, y: 300), to: CGPoint(x: 2, y: 300), delta: CGVector(dx: 4, dy: 0)) == .pass)
        #expect(router.route(from: CGPoint(x: 800, y: 2), to: CGPoint(x: 800, y: -2), delta: CGVector(dx: 0, dy: -4)) == .pass)
        #expect(router.route(from: CGPoint(x: -500, y: -1058), to: CGPoint(x: -500, y: -1062), delta: CGVector(dx: 0, dy: -4)) == .pass)
    }
}

@Suite struct WallTests {
    @Test func wallBlocksATouchingNeighbour() {
        let router = CursorRouter(displays: grid, walls: [EdgeRef(displayID: "TL", edge: .right)])
        let decision = router.route(from: CGPoint(x: 998, y: 500), to: CGPoint(x: 1003, y: 500), delta: CGVector(dx: 5, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: 999, y: 500)))
    }

    @Test func wallHoldsFromTheOtherSideToo() {
        let router = CursorRouter(displays: grid, walls: [EdgeRef(displayID: "TL", edge: .right)])
        let decision = router.route(from: CGPoint(x: 1002, y: 500), to: CGPoint(x: 998, y: 500), delta: CGVector(dx: -4, dy: 0))
        #expect(decision == .warp(to: CGPoint(x: 1000, y: 500)))
    }

    @Test func linkedEdgeIsOnlyReachableThroughItsLink() {
        let link = EdgeLink(EdgeRef(displayID: "TR", edge: .bottom), EdgeRef(displayID: "BL", edge: .top))
        let router = CursorRouter(displays: grid, links: [link])
        let decision = router.route(from: CGPoint(x: 500, y: 1002), to: CGPoint(x: 500, y: 998), delta: CGVector(dx: 0, dy: -4))
        #expect(decision == .warp(to: CGPoint(x: 1500, y: 799)))
    }
}

@Suite struct FacingTests {
    @Test func touchingStretchStopsWhereTheNeighbourEnds() {
        let frames = grid.map(\.virtualFrame)
        #expect(VirtualLayout.facingStretches(from: 0, edge: .right, in: frames) == [FacingStretch(targetIndex: 1, span: 0..<800, gap: 0)])
    }

    @Test func gapStretchCarriesItsWidth() {
        let frames = grid.map(\.virtualFrame)
        #expect(VirtualLayout.facingStretches(from: 1, edge: .bottom, in: frames) == [FacingStretch(targetIndex: 3, span: 1000..<2000, gap: 200)])
    }
}

/// Events recorded on the desk right after a jump from display 4 into display 1 at (-15, -814.1).
@Suite struct PendingMoveTests {
    private let move = PendingMove(target: CGPoint(x: -15, y: -814.1), postedAt: 1_000)

    @Test func eventStillAtTheOldEdgeIsStale() {
        #expect(move.isStale(location: CGPoint(x: 36, y: -811.3), delta: CGVector(dx: -3, dy: 3), now: 4_000_000))
    }

    @Test func eventNearTheTargetIsNotStale() {
        #expect(!move.isStale(location: CGPoint(x: -18, y: -812), delta: CGVector(dx: -3, dy: 2), now: 4_000_000))
    }

    @Test func moveThatNeverLandsStopsFilteringAfterItsLifetime() {
        #expect(!move.isStale(location: CGPoint(x: 36, y: -811.3), delta: CGVector(dx: -3, dy: 3), now: 1_000 + PendingMove.lifetimeNanoseconds))
    }
}

/// Two monitors side by side above a narrower laptop, as macOS reports them. Only the laptop's
/// 0..<1728 span has a display straight above it; the monitors' outer parts face nothing.
@Suite struct SidewaysTests {
    private let left = display("L", CGRect(x: -1696, y: -1440, width: 2560, height: 1440))
    private let right = display("R", CGRect(x: 864, y: -1440, width: 2560, height: 1440))
    private let laptop = display("P", CGRect(x: 0, y: 0, width: 1728, height: 1117))

    private func router(reachesSideways: Bool, walls: Set<EdgeRef> = []) -> CursorRouter {
        CursorRouter(
            displays: VirtualLayout.place([left, right, laptop], origins: [:], mode: .logical),
            jumpsGaps: true,
            walls: walls,
            reachesSideways: reachesSideways
        )
    }

    private func pushDown(at x: CGFloat) -> (from: CGPoint, to: CGPoint, delta: CGVector) {
        (CGPoint(x: x, y: -3), CGPoint(x: x, y: -1.0 / 64), CGVector(dx: 0, dy: 4))
    }

    @Test func outerEdgeIsAWallWithoutTheOption() {
        let move = pushDown(at: -1000)
        #expect(router(reachesSideways: false).route(from: move.from, to: move.to, delta: move.delta) == .pass)
    }

    @Test func leftMonitorReachesTheLaptopsNearestCorner() {
        let move = pushDown(at: -1000)
        #expect(router(reachesSideways: true).route(from: move.from, to: move.to, delta: move.delta)
            == .warp(to: CGPoint(x: 0, y: 3.984375)))
    }

    @Test func rightMonitorReachesTheLaptopsNearestCorner() {
        let move = pushDown(at: 3000)
        #expect(router(reachesSideways: true).route(from: move.from, to: move.to, delta: move.delta)
            == .warp(to: CGPoint(x: 1727, y: 3.984375)))
    }

    @Test func displayStraightBelowStillWins() {
        let router = router(reachesSideways: true)
        #expect(router.route(from: CGPoint(x: 500, y: -2), to: CGPoint(x: 500, y: 2), delta: CGVector(dx: 0, dy: 4)) == .pass)
    }

    @Test func walledTargetEdgeStillHolds() {
        let move = pushDown(at: -1000)
        let router = router(reachesSideways: true, walls: [EdgeRef(displayID: "P", edge: .top)])
        #expect(router.route(from: move.from, to: move.to, delta: move.delta) == .pass)
    }

    @Test func gapLeftAsAWallIsNotBypassedSideways() {
        // Gap jumping off: the laptop straight below, across a gap, must stay unreachable.
        let gapped = ["L": CGPoint(x: -1696, y: -1440), "R": CGPoint(x: 864, y: -1440), "P": CGPoint(x: 0, y: 200)]
        let router = CursorRouter(
            displays: VirtualLayout.place([left, right, laptop], origins: gapped, mode: .logical),
            reachesSideways: true
        )
        let move = pushDown(at: 500)
        #expect(router.route(from: move.from, to: move.to, delta: move.delta) == .pass)
    }

    @Test func sidewaysReachDoesNotGoBackwards() {
        // Pushing up from the top of a monitor: nothing lies above, so nothing is reached.
        let router = router(reachesSideways: true)
        #expect(router.route(from: CGPoint(x: -1000, y: -1437), to: CGPoint(x: -1000, y: -1440), delta: CGVector(dx: 0, dy: -4)) == .pass)
    }

    @Test func sidewaysReachesCoverOnlyTheUnfacedStretches() {
        let frames = VirtualLayout.place([left, right, laptop], origins: [:], mode: .logical).map(\.virtualFrame)
        let reaches = VirtualLayout.sidewaysReaches(in: frames)
        #expect(reaches.contains(SidewaysReach(sourceIndex: 0, edge: .bottom, span: -1696..<0, targetIndex: 2)))
        #expect(reaches.contains(SidewaysReach(sourceIndex: 1, edge: .bottom, span: 1728..<3424, targetIndex: 2)))
        #expect(reaches.count == 2)
    }

    @Test func laptopIsTheNearestDisplayBelowTheLeftMonitor() {
        let placed = VirtualLayout.place([left, right, laptop], origins: [:], mode: .logical)
        #expect(VirtualLayout.nearestBeyond(from: 0, edge: .bottom, in: placed.map(\.virtualFrame)) == 2)
    }
}
