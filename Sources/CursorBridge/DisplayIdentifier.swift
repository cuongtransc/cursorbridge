import AppKit
import CursorBridgeCore
import SwiftUI

@MainActor
enum DisplayIdentifier {
    private static var panels: [NSPanel] = []
    private static var generation = 0

    static func flash(_ displays: [Display], for duration: Duration = .seconds(2.5)) {
        panels.forEach { $0.close() }
        panels = displays.enumerated().compactMap { index, display in
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { return nil }
            return makePanel(on: screen, number: index + 1, name: display.name)
        }
        generation += 1
        let shownGeneration = generation
        Task {
            try? await Task.sleep(for: duration)
            guard shownGeneration == generation else { return }
            panels.forEach { $0.close() }
            panels = []
        }
    }

    private static func makePanel(on screen: NSScreen, number: Int, name: String) -> NSPanel {
        let size = CGSize(width: 360, height: 220)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: IdentifyBadge(number: number, name: name))
        panel.orderFrontRegardless()
        return panel
    }
}

private struct IdentifyBadge: View {
    let number: Int
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 110, weight: .bold, design: .rounded))
            Text(name)
                .font(.title2.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
    }
}
