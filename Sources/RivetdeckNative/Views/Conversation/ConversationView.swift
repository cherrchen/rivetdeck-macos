import SwiftUI

/// The docked conversation surface: a turn-folded timeline over the base
/// background, the error notice, and the composer with a short top fade.
struct ConversationView: View {
    @Bindable var model: AppModel
    var session: NativeSession
    /// Per-turn disclosure overrides; defaults come from live state and the
    /// auto-collapse preference.
    @State private var expandedOverrides: [String: Bool] = [:]
    private var turns: [Turn] { buildTurns(session.entries, running: session.status == "running") }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Spacing.xxl) {
                        if session.evicted {
                            Label("Earlier live rows were released from memory. DSH retains its own session log.", systemImage: "archivebox")
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.Color.labelSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, Tokens.Spacing.sm)
                        }
                        ForEach(turns) { turn in
                            TurnView(turn: turn, model: model,
                                     expanded: expansionBinding(for: turn))
                        }
                        if session.status == "running" {
                            RunningRow(since: session.runningSince)
                        }
                        Color.clear.frame(height: 1).id("tail")
                    }
                    .padding(.horizontal, Tokens.Spacing.xxl)
                    .padding(.vertical, Tokens.Spacing.xl)
                    .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: session.entries.count) { _, _ in proxy.scrollTo("tail", anchor: .bottom) }
                .onChange(of: session.id) { _, _ in proxy.scrollTo("tail", anchor: .bottom) }
            }
            composerDock
        }
    }
    private var composerDock: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            if let error = model.error {
                NoticeView(text: error) { model.error = nil }
            }
            ComposerView(model: model, style: .docked, connect: !model.connected)
            Text("Live events only — no history replay, cancel or approval replies.")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.Color.labelCaption)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Tokens.Spacing.xxl)
        .padding(.bottom, Tokens.Spacing.md)
        .frame(maxWidth: Tokens.Layout.contentMaxWidth + Tokens.Spacing.xxl * 2)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Tokens.Color.base.opacity(0), Tokens.Color.base],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .offset(y: -24),
            alignment: .top
        )
    }
    private func expansionBinding(for turn: Turn) -> Binding<Bool> {
        Binding(
            get: { expandedOverrides[turn.id] ?? (turn.live || !model.autoCollapseWork) },
            set: { expandedOverrides[turn.id] = $0 }
        )
    }
}

private struct TurnView: View {
    var turn: Turn
    var model: AppModel
    @Binding var expanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            if let user = turn.user {
                UserMessageRow(entry: user, model: model)
            }
            if !turn.process.isEmpty {
                TurnProcessRow(turn: turn, model: model, expanded: $expanded)
            }
            if let final = turn.final {
                AssistantRow(entry: final, model: model)
            }
            ForEach(turn.errors) { entry in
                ErrorRow(entry: entry)
            }
        }
    }
}
