import SwiftUI
import AppKit

/// Window shell: NavigationSplitView sidebar + detail conversation + right inspector,
/// the native expression of the DSH three-column AppFrame.
struct MainWindow: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: Tokens.Sidebar.min, ideal: Tokens.Sidebar.ideal, max: Tokens.Sidebar.max)
        } detail: {
            detail
                .background(Tokens.Color.base)
                .navigationTitle(model.selected?.title ?? "Rivetdeck")
                .navigationSubtitle(subtitle)
                .inspector(isPresented: $model.inspectorVisible) {
                    InspectorView(model: model)
                        .inspectorColumnWidth(min: Tokens.Inspector.min, ideal: Tokens.Inspector.ideal, max: Tokens.Inspector.max)
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { Task { await model.newSession() } } label: {
                            Label("New Session", systemImage: Tokens.Icon.newSession)
                        }
                        .disabled(!model.connected || model.sessions.count >= 16)
                    }
                    ToolbarItem {
                        Menu {
                            if let session = model.selected {
                                Button("Copy Session ID", systemImage: "doc.on.doc") {
                                    model.copyToPasteboard(session.id)
                                }
                                Button("Rename…", systemImage: "pencil") { model.beginRename(session.id) }
                                Divider()
                            }
                            Button("Resume Session by ID…", systemImage: Tokens.Icon.resume) { model.showingResume = true }
                                .disabled(!model.connected)
                            Button("Runtime Diagnostics", systemImage: Tokens.Icon.diagnostics) {
                                model.inspectorTab = .diagnostics; model.inspectorVisible = true
                            }
                        } label: {
                            Label("Session", systemImage: "ellipsis.circle")
                        }
                    }
                    ToolbarItem {
                        Button { model.inspectorVisible.toggle() } label: {
                            Label("Inspector", systemImage: Tokens.Icon.inspector)
                        }
                        .keyboardShortcut("i", modifiers: [.option, .command])
                        .help("Toggle the session inspector")
                    }
                }
        }
        .tint(Tokens.Color.brand)
        .preferredColorScheme(model.appearance.scheme)
        .sheet(isPresented: $model.showingResume) { resumeSheet }
    }
    private var subtitle: String {
        guard !model.workspace.isEmpty else { return model.model }
        return "\(URL(fileURLWithPath: model.workspace).lastPathComponent) · \(model.model)"
    }
    @ViewBuilder private var detail: some View {
        if let session = model.selected, session.hasPrompted || session.entries.contains(where: { $0.kind != .activity && $0.kind != .context }) {
            ConversationView(model: model, session: session)
        } else {
            HeroView(model: model)
        }
    }
    private var resumeSheet: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Label("Resume a DSH Session", systemImage: Tokens.Icon.resume)
                .font(.title3.weight(.semibold))
            Text("Enter an ID created under this app’s DSH home. The SDK resumes the Agent but replays no messages; there is no session catalog to browse.")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Session ID", text: $model.resumeID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button("Cancel") { model.showingResume = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Resume") { Task { await model.resume() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.resumeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Tokens.Spacing.xxl)
        .frame(width: 460)
    }
}
