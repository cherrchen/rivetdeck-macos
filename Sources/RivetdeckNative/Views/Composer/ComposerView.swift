import SwiftUI

/// Composer card, mirroring the DSH Web InputBar: draft editor on top, a bottom
/// toolbar with read-only model/permission chips and Send. The model route and
/// permission profile are honest readouts — the SDK applies routes at connect
/// and owns permission policy.
struct ComposerView: View {
    enum Style { case docked, hero }
    @Bindable var model: AppModel
    var style: Style
    /// Hero-disconnected mode: composer rendered disabled with a Connect action
    /// in place of the send button.
    var connect = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    private var promptBytes: Int { model.prompt.utf8.count }
    private var overLimit: Bool { promptBytes > 262144 }
    private var canSend: Bool {
        model.connected && !model.busy && !overLimit &&
        !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var placeholder: String {
        if connect || !model.connected { return "Connect the runtime to start" }
        return style == .hero ? "Describe what you want to build…" : "Message the Agent…"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            ZStack(alignment: .topLeading) {
                // Invisible mirror drives the card height; TextEditor overlays it
                // and scrolls once content exceeds the 240pt clamp.
                Text(model.prompt + " ")
                    .font(.system(size: model.contentTextSize.points))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8).padding(.leading, 5)
                    .hidden()
                    .frame(maxWidth: .infinity, minHeight: style == .hero ? 52 : 36, maxHeight: 240, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    .overlay {
                        TextEditor(text: $model.prompt)
                            .font(.system(size: model.contentTextSize.points))
                            .scrollContentBackground(.hidden)
                            .focused($focused)
                            .disabled(connect || !model.connected)
                            .accessibilityLabel("Prompt")
                            .onAppear { focused = model.connected }
                    }
                if model.prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: model.contentTextSize.points))
                        .foregroundStyle(Tokens.Color.labelCaption)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.top, Tokens.Spacing.sm)
            HStack(spacing: Tokens.Spacing.sm) {
                modelChip
                permissionChip
                if promptBytes > 200_000 {
                    Text("\(promptBytes) / 262144 bytes")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(overLimit ? Tokens.Color.statusError : Tokens.Color.statusWarning)
                }
                Spacer()
                Text("⌘↩")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.labelCaption)
                if connect {
                    Button("Connect") { Task { await model.connect() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.workspace.isEmpty)
                } else {
                    Button { Task { await model.send() } } label: {
                        Image(systemName: Tokens.Icon.send)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Tokens.Color.brand))
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, 6)
        }
        .padding(.top, Tokens.Spacing.xxs)
        .background(Tokens.Color.inputSurface, in: RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                .strokeBorder(Tokens.Color.borderL2, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.06), radius: 12, y: 2)
    }
    private var modelChip: some View {
        Menu {
            Text("Provider: \(model.provider)")
            Text("Model: \(model.model)")
            Divider()
            SettingsLink { Text("Change in Settings…") }
        } label: {
            chipLabel(model.model)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Model route applies at connect; change it in Settings, then reconnect.")
    }
    private var permissionChip: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: "lock.shield")
            Text("Ask")
        }
        .modifier(ChipModifier())
        .help("SDK Profile: workspace-write + ask. The SDK has no approval answerer, so approvals fail closed.")
    }
    private func chipLabel(_ title: String) -> some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
        }
        .modifier(ChipModifier())
    }
}

private struct ChipModifier: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Tokens.Color.labelSecondary)
            .frame(height: 26)
            .padding(.horizontal, Tokens.Spacing.sm)
            .background(hovering ? Tokens.Color.hoverFill : .clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
            .onHover { hovering = $0 }
    }
}
