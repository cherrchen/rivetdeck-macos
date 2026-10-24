import SwiftUI
#if SWIFT_PACKAGE
import RivetdeckCore
#endif

/// Full-width sidebar action button styled after the DSH Web sidebar primary
/// control; reveals the keyboard hint on hover.
private struct SidebarButtonStyle: ButtonStyle {
    var disabled: Bool
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            configuration.label
            Spacer(minLength: 0)
            if hovering {
                Text("⌘N")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.labelCaption)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .padding(.horizontal, Tokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(SwiftUI.Color.white.opacity(hovering ? hoverOpacity : fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .strokeBorder(Tokens.Color.borderL3, lineWidth: 0.5)
        )
        .opacity(disabled ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
        .onHover { hovering = $0 }
    }
    @Environment(\.colorScheme) private var scheme
    private var fillOpacity: Double { scheme == .dark ? 0.15 : 0.55 }
    private var hoverOpacity: Double { scheme == .dark ? 0.20 : 0.30 }
}

/// Translucent DSH blue wash painted behind the sidebar; native vibrancy still
/// shows through. Omitted when Reduce Transparency is on.
private struct SidebarWash: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if !reduceTransparency {
            let top: Double = scheme == .dark ? 0.08 : 0.10
            let bottom: Double = scheme == .dark ? 0.07 : 0.09
            LinearGradient(stops: [
                .init(color: SwiftUI.Color(red: 122/255, green: 155/255, blue: 240/255).opacity(top), location: 0),
                .init(color: .clear, location: 0.35),
                .init(color: .clear, location: 0.68),
                .init(color: SwiftUI.Color(red: 143/255, green: 137/255, blue: 184/255).opacity(bottom), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Left column, mirroring the DSH Web sidebar: brand, New Session, one workspace
/// section with session rows, and a compact footer with runtime state.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var workspaceHover = false
    private var workspaceName: String {
        model.workspace.isEmpty ? "No workspace" : URL(fileURLWithPath: model.workspace).lastPathComponent
    }
    private var workspaceLocked: Bool { model.connected || model.busy }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: Tokens.Icon.brand)
                    .font(.title3)
                    .foregroundStyle(Tokens.Color.brand)
                    .accessibilityHidden(true)
                Text("Rivetdeck")
                    .font(.system(size: 15, weight: .semibold))
                PreviewBadge()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.top, Tokens.Spacing.sm)

            Button { Task { await model.newSession() } } label: {
                Label("New Session", systemImage: Tokens.Icon.newSession)
            }
            .buttonStyle(SidebarButtonStyle(disabled: !model.connected || model.sessions.count >= 16))
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!model.connected || model.sessions.count >= 16)
            .help(model.connected ? "New session in \(workspaceName)" : "Connect the runtime first")
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm)

            List(selection: $model.selection) {
                Section {
                    if model.workspace.isEmpty {
                        Button { model.chooseWorkspace() } label: {
                            Label("Choose Workspace…", systemImage: Tokens.Icon.workspace)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                                .strokeBorder(Tokens.Color.borderL4, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        )
                        .selectionDisabled()
                    } else {
                        ForEach(model.visibleSessions) { session in
                            SessionRowView(session: session, model: model)
                        }
                        if model.visibleSessions.isEmpty {
                            Text(model.sessions.isEmpty ? "No sessions yet" : "No matches")
                                .font(.system(size: 13))
                                .foregroundStyle(Tokens.Color.labelTertiary)
                                .selectionDisabled()
                        }
                    }
                } header: { workspaceHeader }
            }
            .listStyle(.sidebar)
            .searchable(text: $model.sessionQuery, placement: .sidebar, prompt: "Filter sessions")

            HStack(spacing: Tokens.Spacing.sm) {
                StatusDot(color: model.runtimeState.dotColor, pulsing: model.runtimeState.isLive)
                Text(runtimeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.labelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(model.connected ? "Disconnect" : "Connect") {
                    Task { if model.connected { await model.shutdown() } else { await model.connect() } }
                }
                .controlSize(.small)
                .disabled(model.busy || (!model.connected && model.workspace.isEmpty))
                SettingsLink {
                    Image(systemName: Tokens.Icon.settings)
                        .foregroundStyle(Tokens.Color.labelSecondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm)
        }
        .background(SidebarWash())
    }
    private var runtimeLabel: String {
        if model.connected, let version = model.runtimeVersion {
            return "\(model.runtimeState.label) · \(version)"
        }
        return model.runtimeState.label
    }
    private var workspaceHeader: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: Tokens.Icon.workspace)
                .foregroundStyle(model.connected ? Tokens.Color.brand : Tokens.Color.labelTertiary)
            Text(workspaceName)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.workspace)
            Spacer(minLength: 0)
            if !model.workspace.isEmpty, workspaceHover {
                Button { Task { await model.newSession() } } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .disabled(!model.connected || model.sessions.count >= 16)
                .help("New session")
                Menu {
                    Button("Open Workspace…") { model.chooseWorkspace() }
                        .disabled(workspaceLocked)
                    Menu("Open Recent") {
                        ForEach(model.workspaces.filter { $0 != model.workspace }, id: \.self) { path in
                            Button(path) { model.openRecent(path) }
                        }
                        if !model.workspaces.isEmpty { Divider() }
                        Button("Clear Menu") { model.clearRecents() }
                            .disabled(model.workspaces.isEmpty)
                    }
                    .disabled(workspaceLocked)
                    Divider()
                    Button("Reveal in Finder") { model.revealWorkspaceInFinder() }
                    Button("Copy Path") { model.copyToPasteboard(model.workspace) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(workspaceLocked ? "Disconnect to change workspace — one runtime owns one workspace" : "Workspace actions")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .onHover { workspaceHover = $0 }
    }
}
