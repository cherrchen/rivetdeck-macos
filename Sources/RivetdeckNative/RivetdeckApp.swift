import AppKit
import SwiftUI

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
                .frame(minWidth: 860, minHeight: 580)
                .onAppear {
                    #if DEBUG
                    let args = CommandLine.arguments
                    if args.dropFirst().first == "--smoke-test" { model.startSmokeTest(arguments: args) }
                    #endif
                }
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") { Task { await model.newSession() } }.keyboardShortcut("n").disabled(!model.connected)
                Button("Open Workspace…") { model.chooseWorkspace() }.keyboardShortcut("o").disabled(model.connected || model.busy)
                Button("Resume Session by ID…") { model.showingResume = true }.disabled(!model.connected)
            }
        }
        Settings { RuntimeSettings(model: model) }
    }
}
