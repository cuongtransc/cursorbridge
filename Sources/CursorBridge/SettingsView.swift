import CursorBridgeCore
import SwiftUI

private typealias Edge = CursorBridgeCore.Edge

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: String?
    @State private var linkPicking = LinkPicking.off

    var body: some View {
        VStack(spacing: 0) {
            if !model.isTrusted {
                PermissionBanner()
            }
            HStack(spacing: 0) {
                canvas
                Divider()
                Sidebar(model: model, selection: $selection, linkPicking: $linkPicking)
                    .frame(width: 340)
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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("Cursor routing", isOn: $model.isEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()
                Spacer()
                Button("Identify Displays", systemImage: "number.square") { DisplayIdentifier.flash(model.displays) }
                Button(linkPicking.isActive ? "Cancel Linking" : "Link Edges…", systemImage: "link") {
                    linkPicking = linkPicking.isActive ? .off : .first
                }
                Button("Reset Layout", systemImage: "arrow.counterclockwise") { model.resetLayout() }
                    .help("Put displays back where System Settings has them.")
            }
            .padding(12)
            Divider()
            if linkPicking.isActive {
                LinkPickingBanner(picking: $linkPicking)
            }
            LayoutEditorView(model: model, selection: $selection, linkPicking: $linkPicking)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            Legend(showsGaps: model.jumpsGaps)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}

private struct Sidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: String?
    @Binding var linkPicking: LinkPicking

    var body: some View {
        Form {
            if let display = selection.flatMap(model.display(withID:)) {
                Section {
                    ForEach([Edge.top, .bottom, .left, .right], id: \.self) { edge in
                        EdgeRuleRow(model: model, edge: EdgeRef(displayID: display.id, edge: edge))
                    }
                } header: {
                    Text("\(model.number(of: display))  \(display.name)")
                        .font(.headline)
                } footer: {
                    Text("\(Int(display.frame.width)) × \(Int(display.frame.height)) pt")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Edges") {
                    Text("Select a display on the left to choose what each of its edges does: follow the layout, act as a wall, or link to another display's edge.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Links and Walls") {
                if model.links.isEmpty && model.walls.isEmpty {
                    Text("None yet. Use an edge's menu above, or Link Edges… to click two edges on the canvas.")
                        .foregroundStyle(.secondary)
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
            }

            Section("Options") {
                Toggle("Jump across gaps", isOn: $model.jumpsGaps)
                Text("When an edge touches nothing, move the cursor to the nearest display facing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Size displays by", selection: $model.sizingMode) {
                    Text("Resolution").tag(SizingMode.logical)
                    Text("Physical size").tag(SizingMode.physical)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private func describe(_ edge: EdgeRef) -> String {
        guard let display = model.display(withID: edge.displayID) else { return "Disconnected · \(edge.edge.title)" }
        return "\(model.number(of: display)) \(edge.edge.title)"
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
                "\(model.number(of: destination.display))" + (destination.acrossGap ? " (across a gap)" : "")
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

    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .green, text: "Touching")
            if showsGaps {
                LegendItem(color: .green.opacity(0.5), text: "Gap jumped", dashed: true)
            }
            LegendItem(color: .orange, text: "Linked")
            LegendItem(color: .red, text: "Wall")
            Spacer()
            Text("Unmarked edges are walls. Click a display to change its edges; drag to move it.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
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
