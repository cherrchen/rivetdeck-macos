import SwiftUI

/// Centered hero covering every non-conversation state, mirroring the DSH Web
/// HeroShell: brand mark, workspace chip, then a context-appropriate card —
/// workspace picker, disabled composer with Connect, live composer, or New
/// Session when connected with nothing selected.
struct HeroView: View {
    @Bindable var model: AppModel
    @State private var pickerHover = false
    private var workspaceName: String {
        model.workspace.isEmpty ? "No workspace" : URL(fileURLWithPath: model.workspace).lastPathComponent
    }
    var body: some View {
        VStack(spacing: Tokens.Spacing.md) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: Tokens.Icon.brand)
                    .font(.system(size: 34))
                    .foregroundStyle(Tokens.Color.brand)
                Text("Into the Unknown")
                    .font(.system(size: 26, weight: .medium))
                PreviewBadge()
            }
            workspaceChip
            if model.workspace.isEmpty {
                workspacePickerCard
            } else if !model.connected {
                if let error = model.error {
                    NoticeView(text: error) { model.error = nil }
                }
                ComposerView(model: model, style: .hero, connect: true)
                SettingsLink {
                    Text("Runtime Settings…")
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            } else if model.selected != nil {
                ComposerView(model: model, style: .hero, connect: false)
            } else {
                Button("New Session") { Task { await model.newSession() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sessions.count >= 16)
            }
            Text("Live events only — the SDK has no session catalog, history replay, per-session cancel or approval replies.")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Color.labelTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Tokens.Spacing.xxl)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var workspaceChip: some View {
        Menu {
            Button("Open Workspace…") { model.chooseWorkspace() }
                .disabled(model.connected || model.busy)
            if !model.workspaces.isEmpty {
                Menu("Open Recent") {
                    ForEach(model.workspaces, id: \.self) { path in
                        Button(path) { model.openRecent(path) }
                    }
                }
                .disabled(model.connected || model.busy)
            }
        } label: {
            HStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: Tokens.Icon.workspace)
                Text(workspaceName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .font(.system(size: 13))
            .foregroundStyle(Tokens.Color.labelSecondary)
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, 5)
            .background(Tokens.Color.hoverFill, in: Capsule())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(model.workspace)
    }
    private var workspacePickerCard: some View {
        Button { model.chooseWorkspace() } label: {
            Text("Choose a workspace to start")
                .font(.system(size: 14))
                .foregroundStyle(pickerHover ? Tokens.Color.brand : Tokens.Color.labelTertiary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                        .strokeBorder(pickerHover ? Tokens.Color.brand : Tokens.Color.borderL4,
                                      style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { pickerHover = $0 }
    }
}

/// DSH `.notice`: warning icon + selectable caption + dismiss, used above the
/// composer card for model/runtime errors.
struct NoticeView: View {
    var text: String
    var onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            Image(systemName: Tokens.Icon.warning)
                .foregroundStyle(Tokens.Color.statusWarning)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Color.labelSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Color.labelTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(Tokens.Spacing.md)
        .background(Tokens.Color.hoverFill, in: RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
    }
}
