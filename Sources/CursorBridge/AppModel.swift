import AppKit
import CursorBridgeCore
import Observation
import OSLog
import ServiceManagement

let routingLog = Logger(subsystem: "dev.cursorbridge.CursorBridge", category: "routing")

struct StoredSettings: Codable, Equatable {
    var isEnabled = true
    var sizingMode = SizingMode.logical
    /// Virtual origins per sizing mode, keyed by display ID.
    var origins: [String: [String: CGPoint]] = [:]
    var jumpsGaps = true
    var links: [EdgeLink] = []
    var walls: [EdgeRef] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StoredSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        sizingMode = try container.decodeIfPresent(SizingMode.self, forKey: .sizingMode) ?? defaults.sizingMode
        origins = try container.decodeIfPresent([String: [String: CGPoint]].self, forKey: .origins) ?? defaults.origins
        jumpsGaps = try container.decodeIfPresent(Bool.self, forKey: .jumpsGaps) ?? defaults.jumpsGaps
        links = try container.decodeIfPresent([EdgeLink].self, forKey: .links) ?? defaults.links
        walls = try container.decodeIfPresent([EdgeRef].self, forKey: .walls) ?? defaults.walls
    }
}

enum EdgeRule: Hashable {
    case automatic
    case wall
    case link(EdgeRef)
}

struct EdgeDestination: Hashable {
    let display: Display
    let acrossGap: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.display.id == rhs.display.id && lhs.acrossGap == rhs.acrossGap }
    func hash(into hasher: inout Hasher) { hasher.combine(display.id); hasher.combine(acrossGap) }
}

@MainActor
@Observable
final class AppModel {
    private(set) var displays: [Display] = []
    private(set) var isTrusted = Permissions.isTrusted
    private(set) var isIntercepting = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var settings: StoredSettings {
        didSet {
            guard settings != oldValue else { return }
            Self.save(settings)
            applyRouting()
        }
    }

    @ObservationIgnored private let interceptor = MouseInterceptor()
    @ObservationIgnored private var displayRefresh: Task<Void, Never>?
    @ObservationIgnored private static let settingsKey = "settings.v1"

    init() {
        settings = Self.loadSettings()
        displays = DisplayProvider.current()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDisplayRefresh() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleDisplayRefresh() }
            }
        }
        routingLog.notice("Launched; accessibility trusted: \(self.isTrusted, privacy: .public), bundle: \(Bundle.main.bundlePath, privacy: .public)")
        if !isTrusted {
            Permissions.requestAccess()
            watchForAccessibilityGrant()
        }
        applyRouting()
    }

    var isEnabled: Bool {
        get { settings.isEnabled }
        set { settings.isEnabled = newValue }
    }

    var sizingMode: SizingMode {
        get { settings.sizingMode }
        set { settings.sizingMode = newValue }
    }

    var jumpsGaps: Bool {
        get { settings.jumpsGaps }
        set { settings.jumpsGaps = newValue }
    }

    var links: [EdgeLink] { settings.links }
    var walls: Set<EdgeRef> { Set(settings.walls) }

    func rule(for edge: EdgeRef) -> EdgeRule {
        if settings.walls.contains(edge) { return .wall }
        if let partner = settings.links.lazy.compactMap({ $0.counterpart(of: edge) }).first { return .link(partner) }
        return .automatic
    }

    /// An edge has exactly one rule, so setting one clears whatever either edge of a new link had before.
    func setRule(_ rule: EdgeRule, for edge: EdgeRef) {
        var updated = settings
        updated.clearRules(for: edge)
        switch rule {
        case .automatic:
            break
        case .wall:
            updated.walls.append(edge)
        case .link(let partner) where partner != edge:
            updated.clearRules(for: partner)
            updated.links.append(EdgeLink(edge, partner))
        case .link:
            break
        }
        settings = updated
    }

    func link(_ a: EdgeRef, _ b: EdgeRef) {
        setRule(.link(b), for: a)
    }

    func removeLink(_ link: EdgeLink) {
        settings.links.removeAll { $0 == link }
    }

    func removeWall(_ edge: EdgeRef) {
        settings.walls.removeAll { $0 == edge }
    }

    /// Where the layout sends the cursor from `edge` when no wall or link overrides it.
    func automaticDestinations(for edge: EdgeRef) -> [EdgeDestination] {
        let placed = placedDisplays
        guard let index = placed.firstIndex(where: { $0.id == edge.displayID }) else { return [] }
        let reserved = walls.union(links.flatMap { [$0.a, $0.b] })
        var destinations: [EdgeDestination] = []
        for stretch in VirtualLayout.facingStretches(from: index, edge: edge.edge, in: placed.map(\.virtualFrame)) {
            let acrossGap = stretch.gap > 0.5
            let target = placed[stretch.targetIndex]
            guard jumpsGaps || !acrossGap,
                  !reserved.contains(EdgeRef(displayID: target.id, edge: edge.edge.opposite))
            else { continue }
            let destination = EdgeDestination(display: target.display, acrossGap: acrossGap)
            if !destinations.contains(destination) { destinations.append(destination) }
        }
        return destinations
    }

    func display(withID id: String) -> Display? {
        displays.first { $0.id == id }
    }

    var placedDisplays: [PlacedDisplay] {
        VirtualLayout.place(displays, origins: settings.origins[sizingMode.rawValue] ?? [:], mode: sizingMode)
    }

    func number(of display: Display) -> Int {
        (displays.firstIndex(of: display) ?? 0) + 1
    }

    func moveDisplay(_ id: String, to origin: CGPoint) {
        var origins = settings.origins[sizingMode.rawValue]
            ?? VirtualLayout.systemOrigins(for: displays, mode: sizingMode)
        origins[id] = origin
        settings.origins[sizingMode.rawValue] = origins
    }

    func resetLayout() {
        settings.origins[sizingMode.rawValue] = nil
    }

    func virtualCursorLocation() -> CGPoint? {
        guard let location = CGEvent(source: nil)?.location,
              let display = placedDisplays.first(where: { $0.display.frame.contains(location) })
        else { return nil }
        return display.toVirtual(location)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("CursorBridge: launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// While displays wake or reconnect macOS can report a partial or empty list and send no further
    /// notice once it settles, so the list is read again a few times after every change.
    private func scheduleDisplayRefresh() {
        refreshDisplays()
        displayRefresh?.cancel()
        displayRefresh = Task {
            for delay in [0.5, 1.5, 3.0, 6.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                refreshDisplays()
            }
        }
    }

    private func refreshDisplays() {
        let current = DisplayProvider.current()
        guard current != displays else { return }
        routingLog.notice("Displays changed: \(self.displays.count, privacy: .public) -> \(current.count, privacy: .public)")
        displays = current
        interceptor.resetTracking()
        applyRouting()
    }

    private func applyRouting() {
        guard isTrusted, isEnabled else {
            interceptor.stop()
            isIntercepting = false
            return
        }
        interceptor.router = CursorRouter(displays: placedDisplays, jumpsGaps: jumpsGaps, links: links, walls: walls)
        let wasIntercepting = isIntercepting
        isIntercepting = interceptor.start()
        if isIntercepting != wasIntercepting || !isIntercepting {
            routingLog.notice("Event tap running: \(self.isIntercepting, privacy: .public); displays: \(self.displays.count, privacy: .public); gap jumping: \(self.jumpsGaps, privacy: .public)")
        }
    }

    private func watchForAccessibilityGrant() {
        Task {
            while !Permissions.isTrusted {
                try? await Task.sleep(for: .seconds(1))
            }
            isTrusted = true
            routingLog.notice("Accessibility access granted")
            applyRouting()
        }
    }

    private static func loadSettings() -> StoredSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(StoredSettings.self, from: data)
        else { return StoredSettings() }
        return settings
    }

    private static func save(_ settings: StoredSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}

private extension StoredSettings {
    mutating func clearRules(for edge: EdgeRef) {
        walls.removeAll { $0 == edge }
        links.removeAll { $0.involves(edge) }
    }
}

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
