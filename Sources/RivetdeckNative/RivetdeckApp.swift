import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import RivetdeckCore
#endif

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // No nested asynchronous termination loop is needed after confirmed teardown.
        if AppModel.shared.runtimeState == .stopped, !AppModel.shared.busy { return .terminateNow }
        Task { await AppModel.shared.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main struct RivetdeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    init() { AppModel.shared.observe() }
    var body: some Scene {
        Window("Rivetdeck Native", id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    #if DEBUG
                    let args = CommandLine.arguments
                    if args.dropFirst().first == "--smoke-test" { model.startSmokeTest(arguments: args) }
                    #endif
                }
        }
        .defaultSize(width: 1160, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") { Task { await model.newSession() } }
                    .keyboardShortcut("n")
                    .disabled(!model.connected)
                Button("Open Workspace…") { model.chooseWorkspace() }
                    .keyboardShortcut("o")
                    .disabled(model.connected || model.busy)
                Menu("Open Recent") {
                    ForEach(model.workspaces, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { model.openRecent(path) }
                    }
                    if !model.workspaces.isEmpty { Divider() }
                    Button("Clear Menu") { model.clearRecents() }
                        .disabled(model.workspaces.isEmpty)
                }
                .disabled(model.connected || model.busy || model.workspaces.isEmpty)
                Divider()
                Button("Resume Session by ID…") { model.showingResume = true }
                    .disabled(!model.connected)
            }
            CommandGroup(after: .sidebar) {
                Button(model.inspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    model.inspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.option, .command])
            }
            CommandMenu("Runtime") {
                Button(model.connected ? "Disconnect Runtime" : "Connect Runtime") {
                    Task { if model.connected { await model.shutdown() } else { await model.connect() } }
                }
                .disabled(model.busy || (!model.connected && model.workspace.isEmpty))
                Button("Runtime Diagnostics") {
                    model.inspectorTab = .diagnostics; model.inspectorVisible = true
                }
            }
        }
        Settings {
            SettingsView(model: model)
                .tint(Tokens.Color.brand)
                .preferredColorScheme(model.appearance.scheme)
        }
    }
}
