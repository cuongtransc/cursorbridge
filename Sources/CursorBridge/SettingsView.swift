import CursorBridgeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var linkPicking = LinkPicking.off

    var body: some View {
        VStack(spacing: 0) {
            if !model.isTrusted {
                PermissionBanner()
            }
            toolbar
                .padding(12)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if linkPicking.isActive {
                        LinkPickingBanner(picking: $linkPicking)
                    }
                    LayoutEditorView(model: model, linkPicking: $linkPicking)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                LinksSidebar(model: model, linkPicking: $linkPicking)
                    .frame(width: 250)
            }
            Divider()
            legend
                .padding(12)
        }
        .frame(minWidth: 820, minHeight: 520)
        .onExitCommand { linkPicking = .off }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Toggle("Routing", isOn: $model.isEnabled)
                .toggleStyle(.switch)
            Picker("Size by", selection: $model.sizingMode) {
                Text("Resolution").tag(SizingMode.logical)
                Text("Physical size").tag(SizingMode.physical)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Physical size lines the cursor up with the real-world position across displays of different pixel density.")
            Toggle("Jump across gaps", isOn: $model.jumpsGaps)
                .help("When an edge touches nothing, send the cursor to the nearest display facing it.")
            Spacer()
            Button("Identify Displays") { DisplayIdentifier.flash(model.displays) }
            Button("Reset Layout") { model.resetLayout() }
                .help("Put displays back where System Settings has them.")
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            LegendItem(color: .green, text: "Touching edges connect")
            if model.jumpsGaps {
                LegendItem(color: .green.opacity(0.5), text: "Shaded gaps are jumped", dashed: true)
            }
            LegendItem(color: .orange, text: "Linked edges connect end to end")
            Spacer()
            Text("Any other edge is a wall.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
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

private struct LinksSidebar: View {
    @Bindable var model: AppModel
    @Binding var linkPicking: LinkPicking

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edge Links")
                .font(.headline)
            Text("Join two edges directly — for displays that don't line up, or to wrap around the desk. A link replaces the layout for that edge.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                linkPicking = linkPicking.isActive ? .off : .first
            } label: {
                Label(linkPicking.isActive ? "Cancel" : "Link Edges…", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if model.links.isEmpty {
                Spacer()
            } else {
                List {
                    ForEach(model.links) { link in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(describe(link.a))
                                Text("↕ " + describe(link.b))
                            }
                            .font(.callout)
                            Spacer()
                            Button {
                                model.removeLink(link)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove link")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(12)
    }

    private func describe(_ ref: EdgeRef) -> String {
        guard let display = model.display(withID: ref.displayID) else {
            return "Disconnected display · \(ref.edge.rawValue)"
        }
        return "\(model.number(of: display)) \(display.name) · \(ref.edge.rawValue)"
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
