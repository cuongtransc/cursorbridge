import AppKit
import SwiftUI

@main
struct CursorBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model, layoutWindow: appDelegate.layoutWindow)
        } label: {
            Image(systemName: appDelegate.model.isIntercepting ? "cursorarrow.motionlines" : "cursorarrow")
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
        window.setContentSize(NSSize(width: 960, height: 640))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    let layoutWindow: LayoutWindowController

    var body: some View {
        Toggle("Enable Cursor Routing", isOn: $model.isEnabled)
        if !model.isTrusted {
            Button("Grant Accessibility Access…") { Permissions.openAccessibilitySettings() }
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
