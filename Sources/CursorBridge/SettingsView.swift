import CursorBridgeCore
import SwiftUI

private typealias Edge = CursorBridgeCore.Edge

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: String?
    @State private var linkPicking = LinkPicking.off

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model)
            Divider()
            if !model.isTrusted {
                PermissionBanner()
            }
            HStack(spacing: 0) {
                canvas
                Divider()
                Sidebar(model: model, selection: $selection, linkPicking: $linkPicking)
                    .frame(width: 360)
            }
        }
        .frame(minWidth: 980, minHeight: 600)
        .onExitCommand { linkPicking = .off }
        #if DEBUG
        .onAppear {
            if let number = ProcessInfo.processInfo.environment["CURSORBRIDGE_SELECT"].flatMap(Int.init),
               model.displays.indices.contains(number - 1) {
                selection = model.displays[number - 1].id
            }
        }
        #endif
        .onChange(of: model.displays.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    private var canvas: some View {
        VStack(alignment: .leading, spacing: 0) {
            if linkPicking.isActive {
                LinkPickingBanner(picking: $linkPicking)
            } else {
                Text("Drag displays to arrange them for the cursor. Click a display to choose what each of its edges does.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            LayoutEditorView(model: model, selection: $selection, linkPicking: $linkPicking)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            Legend(showsGaps: model.jumpsGaps, showsSideways: model.reachesSideways)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}

private struct Toolbar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcon.image(size: 22))
            Text("CursorBridge")
                .font(.headline)
            StatusPill(status: model.status)
            Spacer()
            Button("Identify Displays", systemImage: "number.square") { DisplayIdentifier.flash(model.displays) }
            Button("Reset to macOS Layout", systemImage: "arrow.counterclockwise") { model.resetLayout() }
                .help("Put displays back where System Settings › Displays has them.")
            Toggle("Routing", isOn: $model.isEnabled)
                .toggleStyle(.switch)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct StatusPill: View {
    let status: RoutingStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(status.title)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15), in: Capsule())
    }
}

private struct Sidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: String?
    @Binding var linkPicking: LinkPicking

    var body: some View {
        Form {
            Section {
                OptionRow(
                    title: "Jump across gaps",
                    detail: "A display straight across an empty gap still counts as next door.",
                    illustration: .gap,
                    isOn: $model.jumpsGaps
                )
                OptionRow(
                    title: "Reach displays off to the side",
                    detail: "Where nothing is straight across, go to the nearest display in that direction. Covers every display at once.",
                    illustration: .sideways,
                    isOn: $model.reachesSideways
                )
            } header: {
                Text("Edges with nothing next to them")
            } footer: {
                Text("Everything else with nothing next to it is a wall.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.links.isEmpty && model.walls.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No custom rules").fontWeight(.semibold)
                        Text("Only needed for one specific path, such as wrapping from the far right back to the far left. A link takes over both edges: each then accepts the cursor only from its partner.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.links) { link in
                    OverrideRow(title: "\(describe(link.a))  ↔  \(describe(link.b))", systemImage: "link", tint: .orange) {
                        model.removeLink(link)
                    }
                }
                ForEach(model.walls.sorted { describe($0) < describe($1) }, id: \.self) { wall in
                    OverrideRow(title: describe(wall), systemImage: "rectangle.portrait.slash", tint: .red) {
                        model.removeWall(wall)
                    }
                }
            } header: {
                HStack {
                    Text("Custom rules")
                    Spacer()
                    Button(linkPicking.isActive ? "Cancel Linking" : "Link Two Edges…", systemImage: "link") {
                        linkPicking = linkPicking.isActive ? .off : .first
                    }
                    .controlSize(.small)
                }
            }

            Section("General") {
                Picker("Size displays by", selection: $model.sizingMode) {
                    Text("Resolution").tag(SizingMode.logical)
                    Text("Physical size").tag(SizingMode.physical)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            if let display = selection.flatMap(model.display(withID:)) {
                Section {
                    ForEach([Edge.top, .bottom, .left, .right], id: \.self) { edge in
                        EdgeRuleRow(model: model, edge: EdgeRef(displayID: display.id, edge: edge))
                    }
                } header: {
                    Text("\(model.number(of: display)) · \(display.name)")
                } footer: {
                    Text("\(Int(display.frame.width)) × \(Int(display.frame.height)) pt")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Edges of one display") {
                    Text("Click a display on the left to see where each of its edges leads, or to make one a wall.")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
    }

    private func describe(_ edge: EdgeRef) -> String {
        guard let display = model.display(withID: edge.displayID) else { return "Disconnected · \(edge.edge.title)" }
        return "\(model.number(of: display)) \(edge.edge.title)"
    }
}

private struct OptionRow: View {
    let title: String
    let detail: String
    let illustration: OptionIllustration.Kind
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OptionIllustration(kind: illustration)
                .frame(width: 56, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: $isOn) {
                    Text(title).fontWeight(.semibold)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Small drawings that show what an option does, in the canvas's own colours.
private struct OptionIllustration: View {
    enum Kind { case gap, sideways }
    let kind: Kind

    var body: some View {
        Canvas { context, _ in
            let outline = GraphicsContext.Shading.color(.secondary)
            func screen(_ rect: CGRect) {
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(path, with: .color(Color(nsColor: .textBackgroundColor)))
                context.stroke(path, with: outline, lineWidth: 1.5)
            }
            switch kind {
            case .gap:
                screen(CGRect(x: 2, y: 8, width: 20, height: 24))
                screen(CGRect(x: 34, y: 8, width: 20, height: 24))
                var line = Path()
                line.move(to: CGPoint(x: 23, y: 20))
                line.addLine(to: CGPoint(x: 33, y: 20))
                context.stroke(line, with: .color(EdgeColors.gap), style: StrokeStyle(lineWidth: 3, dash: [3, 2]))
            case .sideways:
                screen(CGRect(x: 2, y: 2, width: 24, height: 14))
                screen(CGRect(x: 30, y: 24, width: 18, height: 14))
                var arrow = Path()
                arrow.move(to: CGPoint(x: 8, y: 17))
                arrow.addCurve(to: CGPoint(x: 29, y: 28), control1: CGPoint(x: 10, y: 26), control2: CGPoint(x: 22, y: 28))
                arrow.move(to: CGPoint(x: 25, y: 25))
                arrow.addLine(to: CGPoint(x: 30, y: 28))
                arrow.addLine(to: CGPoint(x: 25, y: 31))
                context.stroke(arrow, with: .color(EdgeColors.sideways), lineWidth: 1.8)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct EdgeRuleRow: View {
    @Bindable var model: AppModel
    let edge: EdgeRef

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(edge.edge.title, selection: Binding(
                get: { model.rule(for: edge) },
                set: { model.setRule($0, for: edge) }
            )) {
                Text("Automatic").tag(EdgeRule.automatic)
                Text("Wall").tag(EdgeRule.wall)
                ForEach(model.displays, id: \.id) { target in
                    Section("Link to \(model.number(of: target)) \(target.name)") {
                        ForEach(Edge.allCases.filter { !(target.id == edge.displayID && $0 == edge.edge) }, id: \.self) { targetEdge in
                            Text("\(model.number(of: target)) · \(targetEdge.title) edge")
                                .tag(EdgeRule.link(EdgeRef(displayID: target.id, edge: targetEdge)))
                        }
                    }
                }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        switch model.rule(for: edge) {
        case .wall:
            return "The cursor stops here."
        case .link(let partner):
            guard let target = model.display(withID: partner.displayID) else { return "Linked to a disconnected display." }
            return "Joined end to end with \(model.number(of: target))'s \(partner.edge.title.lowercased()) edge."
        case .automatic:
            let destinations = model.automaticDestinations(for: edge)
            guard !destinations.isEmpty else { return "Nothing here, so the cursor stops." }
            return "Leads to " + destinations.map { destination in
                "\(model.number(of: destination.display))" + destination.route.note
            }.formatted(.list(type: .and)) + "."
        }
    }
}

private struct OverrideRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let remove: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(tint)
            Spacer()
            Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Legend: View {
    let showsGaps: Bool
    let showsSideways: Bool

    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: EdgeColors.touching, text: "Edges touch")
            if showsGaps {
                LegendItem(color: EdgeColors.gap, text: "Jumps a gap", dashed: true)
            }
            if showsSideways {
                LegendItem(color: EdgeColors.sideways, text: "Reaches sideways", dashed: true)
            }
            LegendItem(color: EdgeColors.link, text: "Linked")
            LegendItem(color: EdgeColors.wall, text: "Wall")
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Your cursor")
            }
            Spacer()
        }
        .font(.caption)
    }
}

/// One colour per way an edge can lead somewhere, shared by the canvas, legend and illustrations.
enum EdgeColors {
    static let touching = Color.green
    static let gap = Color.green.opacity(0.6)
    static let sideways = Color.teal
    static let link = Color.orange
    static let wall = Color.red
}

private struct LegendItem: View {
    let color: Color
    let text: String
    var dashed = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [3, 2] : []))
                .frame(width: 18, height: 6)
            Text(text)
        }
    }
}

private struct LinkPickingBanner: View {
    @Binding var picking: LinkPicking

    var body: some View {
        HStack {
            Image(systemName: "link")
            Text(picking == .first
                 ? "Click near the edge of the first display."
                 : "Now click the edge to join it to. Click the same edge again to pick a different one.")
            Spacer()
            Button("Cancel") { picking = .off }
        }
        .font(.callout)
        .padding(10)
        .background(.orange.opacity(0.18))
    }
}

private struct PermissionBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("CursorBridge needs Accessibility access to move the cursor between displays.")
            Spacer()
            Button("Open System Settings") { Permissions.openAccessibilitySettings() }
        }
        .padding(12)
        .background(.yellow.opacity(0.15))
    }
}

private extension EdgeDestination.Route {
    var note: String {
        switch self {
        case .touching: ""
        case .acrossGap: " (across a gap)"
        case .sideways: " (off to the side)"
        }
    }
}

extension CursorBridgeCore.Edge {
    var title: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .left: "Left"
        case .right: "Right"
        }
    }
}
