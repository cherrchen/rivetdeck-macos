import SwiftUI
import AppKit

struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var showingDiagnostics = false
    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Workspace") {
                    Label(model.workspace.isEmpty ? "No workspace selected" : URL(fileURLWithPath: model.workspace).lastPathComponent, systemImage: "folder")
                        .help(model.workspace)
                    Button("Open Workspace…", systemImage: "folder.badge.plus") { model.chooseWorkspace() }
                        .disabled(model.connected || model.busy)
                    ForEach(model.workspaces.filter { $0 != model.workspace }, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { model.workspace = path }
                            .help(path).disabled(model.connected || model.busy)
                    }
                }
                Section("Sessions · \(model.sessions.count)") {
                    ForEach(model.sessions) { session in
                        HStack {
                            Image(systemName: session.status == "running" ? "circle.dotted.circle" : "bubble.left")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title).lineLimit(2)
                                Text(session.status.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(session.id)
                        .contextMenu {
                            Button("Copy Session ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(session.id, forType: .string)
                            }
                        }
                    }
                    Button("New Session", systemImage: "square.and.pencil") { Task { await model.newSession() } }
                        .disabled(!model.connected || model.sessions.count >= 16)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(model.connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
                        Text(model.runtimeState.label).font(.callout)
                        Spacer()
                        Button { showingDiagnostics = true } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.plain).help("Runtime diagnostics")
                    }
                    Button(model.connected ? "Disconnect Runtime" : "Connect Runtime") {
                        Task { if model.connected { await model.shutdown() } else { await model.connect() } }
                    }.disabled(model.busy)
                    SettingsLink { Label("Settings", systemImage: "gearshape") }.buttonStyle(.plain).font(.caption)
                }
                .padding().background(.bar)
            }
        } detail: {
            VStack(spacing: 0) {
                if let session = model.selected { conversation(session) }
                else {
                    ContentUnavailableView {
                        Label("Rivetdeck Native", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Open a workspace, check Runtime settings, and connect to DeepSeek Harness.")
                    } actions: {
                        Button("Connect Runtime") { Task { await model.connect() } }.disabled(model.busy || model.connected)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error = model.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                    }.padding(12).background(Color.orange.opacity(0.08))
                }
            }
            .navigationTitle(model.selected?.title ?? "Rivetdeck Native")
            .toolbar {
                ToolbarItem {
                    Button { Task { await model.newSession() } } label: { Label("New Session", systemImage: "square.and.pencil") }
                        .disabled(!model.connected || model.sessions.count >= 16)
                }
                ToolbarItem { Text(model.activeCount > 0 ? "\(model.activeCount) running" : model.runtimeState.label).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Runtime Diagnostics").font(.title2)
                Text("Logs contain connection metadata only. Runtime stderr is drained without displaying raw plugin output or credentials.").foregroundStyle(.secondary)
                ScrollView { Text(model.logs.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Done") { showingDiagnostics = false }.keyboardShortcut(.defaultAction)
            }.padding(24).frame(width: 560, height: 360)
        }
        .sheet(isPresented: $model.showingResume) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Resume a DSH Session").font(.title2)
                Text("Enter an ID from this app’s DSH home. SDK resumes the Agent, but does not replay previous messages or list saved sessions.")
                TextField("Session ID", text: $model.resumeID).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { model.showingResume = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Resume") { Task { await model.resume() } }.keyboardShortcut(.defaultAction).disabled(model.resumeID.isEmpty)
                }
            }.padding(24).frame(width: 480)
        }
    }
    private func conversation(_ session: NativeSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label(session.workspace, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(session.status.capitalized)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        Text("Live events only · SDK has no history replay, per-session stop, or approval replies. Output appears when DSH records it.")
                            .font(.caption).foregroundStyle(.secondary)
                        if session.evicted { Text("Earlier live rows were released from memory. DSH retains its own session log.").font(.caption).foregroundStyle(.secondary) }
                        if session.entries.isEmpty {
                            Text("Ready when you are.").font(.title2).foregroundStyle(.secondary).padding(.vertical, 30)
                        }
                        ForEach(session.entries) { entry in
                            if entry.role == "activity" {
                                Label(entry.text, systemImage: "bolt.horizontal").font(.caption).foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(entry.role.capitalized).font(.caption.weight(.semibold)).foregroundStyle(entry.role == "error" ? Color.orange : Color.secondary)
                                    Text(entry.text.isEmpty ? "[Non-text content]" : entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("tail")
                    }.padding(24).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
                }
                .onChange(of: session.entries.count) { _, _ in proxy.scrollTo("tail", anchor: .bottom) }
                .onChange(of: session.id) { _, _ in proxy.scrollTo("tail", anchor: .bottom) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $model.prompt)
                    .font(.body).scrollContentBackground(.hidden)
                    .frame(minHeight: 64, maxHeight: 130).accessibilityLabel("Prompt")
                HStack {
                    Text("\(model.provider) / \(model.model)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Send", systemImage: "arrow.up") { Task { await model.send() } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.connected || model.busy || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(16).background(.bar)
        }
    }
}
