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

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StoredSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        sizingMode = try container.decodeIfPresent(SizingMode.self, forKey: .sizingMode) ?? defaults.sizingMode
        origins = try container.decodeIfPresent([String: [String: CGPoint]].self, forKey: .origins) ?? defaults.origins
        jumpsGaps = try container.decodeIfPresent(Bool.self, forKey: .jumpsGaps) ?? defaults.jumpsGaps
        links = try container.decodeIfPresent([EdgeLink].self, forKey: .links) ?? defaults.links
    }
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
    @ObservationIgnored private static let settingsKey = "settings.v1"

    init() {
        settings = Self.loadSettings()
        displays = DisplayProvider.current()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
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

    /// Each edge carries at most one link, so linking an edge replaces whatever it was linked to.
    func link(_ a: EdgeRef, _ b: EdgeRef) {
        guard a != b else { return }
        settings.links = settings.links.filter { !$0.involves(a) && !$0.involves(b) } + [EdgeLink(a, b)]
    }

    func removeLink(_ link: EdgeLink) {
        settings.links.removeAll { $0 == link }
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

    private func refreshDisplays() {
        displays = DisplayProvider.current()
        interceptor.resetTracking()
        applyRouting()
    }

    private func applyRouting() {
        guard isTrusted, isEnabled else {
            interceptor.stop()
            isIntercepting = false
            return
        }
        interceptor.router = CursorRouter(displays: placedDisplays, jumpsGaps: jumpsGaps, links: links)
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
