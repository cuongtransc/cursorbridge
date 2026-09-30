import CoreGraphics
import CursorBridgeCore
import Darwin

/// Session event tap that re-routes the cursor at display edges.
///
/// The tap's run-loop source is attached to the main run loop, so every callback and every
/// mutation from `AppModel` happens on the main thread.
final class MouseInterceptor: @unchecked Sendable {
    var router: CursorRouter?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastLocation: CGPoint?
    /// When the last warp happened, in the clock the event timestamps use.
    private var lastWarpStamp: UInt64?
    private var timestampsUseMachTicks: Bool?
    private var pendingMove: PendingMove?

    private static let movedEventMarker: Int64 = 0x4342_5247
    private let moveSource: CGEventSource? = {
        let source = CGEventSource(stateID: .hidSystemState)
        // Posting normally suppresses local mouse input for 250 ms, which stalls the cursor after a jump.
        source?.localEventsSuppressionInterval = 0
        source?.userData = movedEventMarker
        return source
    }()

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        lastLocation = nil
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.runLoopSource = nil
    }

    func resetTracking() {
        lastLocation = nil
        lastWarpStamp = nil
        pendingMove = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            lastLocation = nil
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.movedEventMarker {
            lastLocation = event.location
            return Unmanaged.passUnretained(event)
        }

        // A fast mouse queues events faster than they are handled. Ones generated before our last warp
        // still carry the pre-warp position; routing them would warp the cursor straight back.
        if let lastWarpStamp, let lastLocation, event.timestamp != 0, event.timestamp <= lastWarpStamp {
            event.location = lastLocation
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        let delta = CGVector(
            dx: event.getDoubleValueField(.mouseEventDeltaX),
            dy: event.getDoubleValueField(.mouseEventDeltaY)
        )

        if let pendingMove, let lastLocation {
            if pendingMove.isStale(location: location, delta: delta, now: clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) {
                event.location = lastLocation
                return Unmanaged.passUnretained(event)
            }
            self.pendingMove = nil
        }

        guard let router, let previous = lastLocation else {
            lastLocation = location
            return Unmanaged.passUnretained(event)
        }
        switch router.route(from: previous, to: location, delta: delta) {
        case .pass:
            lastLocation = location
        case .warp(let target):
            routingLog.debug("warp \(location.debugDescription, privacy: .public) -> \(target.debugDescription, privacy: .public) delta \(delta.dx, privacy: .public),\(delta.dy, privacy: .public) ts \(event.timestamp, privacy: .public)")
            lastLocation = target
            let movedByEvent = post(type, at: target, replacing: event)
            if !movedByEvent {
                CGWarpMouseCursorPosition(target)
                CGAssociateMouseAndMouseCursorPosition(1)
                event.location = target
            }
            lastWarpStamp = eventClockNow(matching: event.timestamp)
            if movedByEvent {
                pendingMove = PendingMove(target: target, postedAt: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    /// Moves the cursor by posting a copy of `original` at `target`; the copy reaches apps in its place.
    private func post(_ type: CGEventType, at target: CGPoint, replacing original: CGEvent) -> Bool {
        let button: CGMouseButton = switch type {
        case .rightMouseDragged: .right
        case .otherMouseDragged: .center
        default: .left
        }
        guard let moved = CGEvent(mouseEventSource: moveSource, mouseType: type, mouseCursorPosition: target, mouseButton: button) else {
            return false
        }
        moved.flags = original.flags
        moved.setIntegerValueField(.mouseEventButtonNumber, value: original.getIntegerValueField(.mouseEventButtonNumber))
        moved.post(tap: .cghidEventTap)
        return true
    }

    /// Event timestamps are documented as nanoseconds but are mach ticks on some hardware,
    /// so the unit is inferred from the first real event.
    private func eventClockNow(matching timestamp: UInt64) -> UInt64 {
        let ticks = mach_absolute_time()
        let nanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if timestampsUseMachTicks == nil, timestamp != 0 {
            let tickGap = ticks > timestamp ? ticks - timestamp : timestamp - ticks
            let nanosecondGap = nanoseconds > timestamp ? nanoseconds - timestamp : timestamp - nanoseconds
            timestampsUseMachTicks = tickGap < nanosecondGap
            routingLog.notice("Event timestamps use \(tickGap < nanosecondGap ? "mach ticks" : "nanoseconds", privacy: .public)")
        }
        return timestampsUseMachTicks == false ? nanoseconds : ticks
    }
}

private func mouseTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<MouseInterceptor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
