import SwiftUI
import AppKit

/// One session in the sidebar: a 16pt status slot and a single-line title with
/// inline rename. Menus expose only honest operations — the SDK has no
/// archive/fork/dispose.
struct SessionRowView: View {
    var session: NativeSession
    @Bindable var model: AppModel
    @FocusState private var renameFocused: Bool
    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            statusSlot
            if model.renamingID == session.id {
                TextField("Title", text: $model.renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($renameFocused)
                    .onSubmit { model.commitRename() }
                    .onKeyPress(.escape) { model.cancelRename(); return .handled }
                    .onAppear { renameFocused = true }
            } else {
                Text(session.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .tag(session.id)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { model.beginRename(session.id) }
            Button("Copy Session ID", systemImage: "doc.on.doc") { model.copyToPasteboard(session.id) }
            Divider()
            Button("Remove from List", systemImage: "minus.circle") { model.removeFromList(session.id) }
                .help("Removes the UI row only; DSH keeps its session. The SDK cannot dispose sessions.")
        }
    }
    @ViewBuilder private var statusSlot: some View {
        switch session.status {
        case "running":
            ProgressView().controlSize(.mini)
                .frame(width: 16, height: 16)
        case "failed":
            StatusDot(color: Tokens.Color.statusError)
                .frame(width: 16, height: 16)
        case "interrupted":
            StatusDot(color: Tokens.Color.statusWarning)
                .frame(width: 16, height: 16)
        default:
            SwiftUI.Color.clear.frame(width: 16, height: 16)
        }
    }
}
