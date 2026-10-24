import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import RivetdeckCore
#endif

/// Right-hand inspector — the native counterpart of the DSH right column.
/// SDK cannot serve file/terminal tabs, so this surfaces session metadata and
/// bounded diagnostics instead of pretending to those capabilities.
struct InspectorView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.inspectorTab) {
                Text("Session").tag(InspectorTab.session)
                Text("Diagnostics").tag(InspectorTab.diagnostics)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Tokens.Spacing.md)
            Divider()
            switch model.inspectorTab {
            case .session: sessionTab
            case .diagnostics: diagnosticsTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var sessionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                if let session = model.selected {
                    group("Session") {
                        row("Title", value: session.title)
                        row("Status", value: session.status.capitalized)
                        idRow("Session ID", value: session.id)
                        row("Created", value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    group("Workspace") {
                        pathRow(session.workspace)
                    }
                    group("Model route") {
                        row("Provider", value: model.provider)
                        row("Model", value: model.model)
                        Text("Applies at connect. Change in Settings, then reconnect.")
                            .font(.system(size: 12)).foregroundStyle(Tokens.Color.labelCaption)
                    }
                    group("Live view") {
                        row("Rows", value: "\(session.entries.count) / 200")
                        Text("Closing a row never deletes the DSH session.")
                            .font(.system(size: 12)).foregroundStyle(Tokens.Color.labelCaption)
                    }
                    group("Not available in the SDK") {
                        ForEach(["History replay", "Per-session cancel", "Approval replies", "Session disposal"], id: \.self) { item in
                            Label(item, systemImage: "minus.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.Color.labelTertiary)
                        }
                    }
                } else {
                    ContentUnavailableView("No Session", systemImage: "bubble.left", description: Text("Select a session to inspect it."))
                        .padding(.top, Tokens.Spacing.xxxl)
                }
            }
            .padding(Tokens.Spacing.md)
        }
    }
    private var diagnosticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                group("Runtime") {
                    row("State", value: model.runtimeState.label)
                    row("SDK version", value: model.runtimeVersion ?? "—")
                    row("Sessions", value: "\(model.sessions.count) (\(model.activeCount) running)")
                }
                group("Paths") {
                    pathRow(model.nodePath, label: "Node")
                    pathRow(model.runtimePath, label: "Runtime")
                    pathRow(model.homePath, label: "DSH home")
                }
                group("Log", trailing: AnyView(copyLogButton)) {
                    if model.logs.isEmpty {
                        Text("No entries yet.").font(.system(size: 12)).foregroundStyle(Tokens.Color.labelCaption)
                    } else {
                        Text(model.logs.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Tokens.Spacing.sm)
                            .background(Tokens.Color.codeBlock, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                    }
                    Text("Metadata only. Runtime stderr is drained and counted without displaying raw plugin output or credentials.")
                        .font(.system(size: 12)).foregroundStyle(Tokens.Color.labelCaption)
                }
            }
            .padding(Tokens.Spacing.md)
        }
    }
    private var copyLogButton: some View {
        Button {
            model.copyToPasteboard(model.logs.joined(separator: "\n"))
        } label: {
            Image(systemName: "doc.on.doc").font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.Color.labelTertiary)
        .disabled(model.logs.isEmpty)
        .help("Copy log")
    }
    private func group(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Color.labelSecondary)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Spacing.md)
                .background(Tokens.Color.hoverFill, in: RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                        .strokeBorder(Tokens.Color.borderL2, lineWidth: 0.5)
                )
        }
    }
    private func row(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(Tokens.Color.labelSecondary)
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
    }
    private func idRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: Tokens.Spacing.xs) {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.Color.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button { model.copyToPasteboard(value) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Color.labelTertiary)
                .help("Copy Session ID")
            }
        }
        .font(.system(size: 12))
    }
    private func pathRow(_ path: String, label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            if let label { Text(label).font(.system(size: 12)).foregroundStyle(Tokens.Color.labelSecondary) }
            Text(path.isEmpty ? "—" : path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Tokens.Color.labelSecondary)
                .textSelection(.enabled)
        }
    }
}
