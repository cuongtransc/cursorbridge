import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // The build runs the binary this way to render AppIcon.icns from the same drawing code,
        // before any of the app (event tap, permission prompt) starts.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--write-iconset"), index + 1 < arguments.count {
            do {
                try MainActor.assumeIsolated { try AppIcon.writeIconset(to: URL(fileURLWithPath: arguments[index + 1])) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("write-iconset failed: \(error)\n".utf8))
                exit(1)
            }
        }
        CursorBridgeApp.main()
    }
}

struct CursorBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model, layoutWindow: appDelegate.layoutWindow)
        } label: {
            Image(nsImage: AppIcon.menuBarImage(for: appDelegate.model.status))
                .accessibilityLabel("CursorBridge, \(appDelegate.model.status.title)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var layoutWindow = LayoutWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // With no window open, macOS would otherwise reclaim the app and the event tap with it.
        ProcessInfo.processInfo.disableAutomaticTermination("Routes the cursor between displays")
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["CURSORBRIDGE_SNAPSHOT"] {
            layoutWindow.show()
            Task {
                try? await Task.sleep(for: .seconds(2))
                layoutWindow.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        if !model.isTrusted {
            layoutWindow.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Menu-bar icons can be hidden behind the notch, so launching the app again opens its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        layoutWindow.show()
        return false
    }
}

@MainActor
final class LayoutWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    #if DEBUG
    func snapshot(to url: URL) {
        guard let view = window?.contentView?.superview,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "CursorBridge Layout"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Tall enough for the whole sidebar without scrolling, short enough for a 1117 pt laptop screen.
        window.setContentSize(NSSize(width: 1100, height: 900))
        window.isReleasedWhenClosed = false
        window.center()
        // A closed window keeps its SwiftUI view alive, and with it the editor's 30 Hz cursor timer.
        // Dropping the window on close stops the timer; the next show() builds a fresh one.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
        return window
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    let layoutWindow: LayoutWindowController

    var body: some View {
        Text(model.status.title)
        if model.isTrusted {
            Toggle("Cursor Routing", isOn: $model.isEnabled)
        } else {
            Button("Grant Access…") { Permissions.openAccessibilitySettings() }
        }
        Divider()
        Section("Edges with nothing next to them") {
            Toggle("Jump Across Gaps", isOn: $model.jumpsGaps)
            Toggle("Reach Displays off to the Side", isOn: $model.reachesSideways)
        }
        Divider()
        Button("Configure Layout…") { layoutWindow.show() }
            .keyboardShortcut(",")
        Button("Identify Displays") { DisplayIdentifier.flash(model.displays) }
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("Quit CursorBridge") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
