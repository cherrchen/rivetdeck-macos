import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import RivetdeckCore
#endif

/// Timeline is built by turns, mirroring the DSH Web conversation: a turn opens
/// at each user message and its process — activity, tool results, context and
/// intermediate assistant text — folds behind a disclosure header.
struct Turn: Identifiable {
    let id: String
    var user: ConversationEntry?
    var process: [ConversationEntry]
    var final: ConversationEntry?
    var errors: [ConversationEntry]
    var live: Bool
}

func buildTurns(_ entries: [ConversationEntry], running: Bool) -> [Turn] {
    var groups: [[ConversationEntry]] = [[]]
    for entry in entries {
        if entry.kind == .user { groups.append([entry]) }
        else { groups[groups.count - 1].append(entry) }
    }
    var turns = groups.enumerated().map { index, group -> Turn in
        var turn = Turn(id: group.first?.id ?? "turn-\(index)", user: group.first?.kind == .user ? group.first : nil,
                        process: [], final: nil, errors: [], live: false)
        var rest = turn.user == nil ? group : Array(group.dropFirst())
        let live = running && index == groups.count - 1
        if !live, let lastAssistant = rest.lastIndex(where: { $0.kind == .assistant }) {
            turn.final = rest[lastAssistant]
            rest.remove(at: lastAssistant)
        }
        turn.errors = rest.filter { $0.kind == .error }
        turn.process = rest.filter { $0.kind != .error }
        turn.live = live
        return turn
    }
    if turns.count == 1, turns[0].user == nil, turns[0].process.isEmpty, turns[0].final == nil, turns[0].errors.isEmpty {
        turns = []
    }
    return turns
}

private func activityIcon(_ activity: Activity?) -> String {
    switch activity {
    case .toolCall: return Tokens.Icon.tool
    case .subagentStarted, .subagentFinished: return Tokens.Icon.subagent
    case .turnEnded: return Tokens.Icon.turnEnded
    case .approval: return Tokens.Icon.approval
    case .other, nil: return Tokens.Icon.activity
    }
}

/// Folded or live process section of a turn — DSH TurnProcessNodeView.
struct TurnProcessRow: View {
    var turn: Turn
    var model: AppModel
    @Binding var expanded: Bool
    @State private var hovering = false
    private var summary: String {
        if turn.live { return "Working · \(turn.process.count) steps" }
        if !turn.errors.isEmpty { return "Failed · \(turn.process.count) steps" }
        if turn.user == nil { return "Session context · \(turn.process.count) steps" }
        return "Completed · \(turn.process.count) steps"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    Text(summary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .font(.system(size: 13))
                .foregroundStyle(hovering ? Tokens.Color.labelSecondary : Tokens.Color.labelTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .padding(.bottom, Tokens.Spacing.sm)
            .overlay(alignment: .bottom) {
                Tokens.Color.borderL2.frame(height: 0.5)
            }
            if expanded {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    ForEach(turn.process) { entry in
                        ProcessStepRow(entry: entry, model: model)
                    }
                }
                .padding(.top, Tokens.Spacing.sm)
            }
        }
    }
}

/// One 24pt disclosure row inside a turn process — DSH DisclosureRow.
private struct ProcessStepRow: View {
    var entry: ConversationEntry
    var model: AppModel
    @State private var expanded = false
    @State private var hovering = false
    var body: some View {
        switch entry.kind {
        case .assistant:
            AssistantRow(entry: entry, model: model)
        case .tool:
            expandable(title: "Result", summary: firstLine(entry.text), icon: Tokens.Icon.tool, detail: entry.text)
        case .context:
            expandable(title: "Context injection", summary: firstLine(entry.text), icon: "arrow.down.doc", detail: entry.text)
        default:
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: activityIcon(entry.activity))
                    .frame(width: 16)
                Text(entry.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 13))
            .foregroundStyle(hovering ? Tokens.Color.labelSecondary : Tokens.Color.labelTertiary)
            .frame(height: 24)
            .onHover { hovering = $0 }
            .contextMenu { Button("Copy") { model.copyToPasteboard(entry.text) } }
        }
    }
    private func firstLine(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }
    private func expandable(title: String, summary: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Button { expanded.toggle() } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: icon)
                        .frame(width: 16)
                    Text(title)
                    Text("· \(summary)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .font(.system(size: 13))
                .foregroundStyle(hovering ? Tokens.Color.labelSecondary : Tokens.Color.labelTertiary)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            if expanded {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Tokens.Spacing.sm)
                }
                .frame(maxHeight: 240)
                .background(Tokens.Color.codeBlock, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
            }
        }
        .contextMenu { Button("Copy") { model.copyToPasteboard(detail) } }
    }
}

/// User prompt: trailing bubble with a hover-revealed time/copy row.
struct UserMessageRow: View {
    var entry: ConversationEntry
    var model: AppModel
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.xs) {
            HStack {
                Spacer(minLength: 80)
                Text(entry.text.isEmpty ? "[Non-text content]" : entry.text)
                    .font(.system(size: model.contentTextSize.points))
                    .textSelection(.enabled)
                    .padding(.horizontal, Tokens.Spacing.lg)
                    .padding(.vertical, 10)
                    .background(Tokens.Color.bubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous))
            }
            if hovering {
                HStack(spacing: Tokens.Spacing.sm) {
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.Color.labelTertiary)
                    Button { model.copyToPasteboard(entry.text) } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

/// Assistant message: inline markdown, no role label, hover action row.
struct AssistantRow: View {
    var entry: ConversationEntry
    var model: AppModel
    @State private var hovering = false
    private var rendered: Text {
        let source = entry.text.isEmpty ? "[Non-text content]" : entry.text
        if let attributed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(source)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            rendered
                .font(.system(size: model.contentTextSize.points))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                HStack(spacing: Tokens.Spacing.sm) {
                    Button { model.copyToPasteboard(entry.text) } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.Color.labelTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.Color.labelTertiary)
                }
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { Button("Copy") { model.copyToPasteboard(entry.text) } }
    }
}

/// Structured turn failure — DSH turnErrorRow: dot + title + message, no box.
struct ErrorRow: View {
    var entry: ConversationEntry
    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            StatusDot(color: Tokens.Color.statusError, size: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text("Agent Error")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Color.statusError)
                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Color.labelSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Live tail row while the session runs: spinner + elapsed seconds.
struct RunningRow: View {
    var since: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            ProgressView().controlSize(.mini)
            TimelineView(.periodic(from: since ?? Date(), by: 1)) { context in
                let seconds = Int(context.date.timeIntervalSince(since ?? context.date))
                Text("Working · \(max(seconds, 0))s")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Tokens.Color.labelTertiary)
        .opacity(reduceMotion ? 1 : (pulsing ? 0.6 : 1.0))
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
    }
}
