import AppKit
import Observation
import SwiftUI
#if SWIFT_PACKAGE
import RivetdeckCore
#endif

@MainActor enum UIPreferences {
    static let store: UserDefaults = {
        if CommandLine.arguments.contains("--smoke-test") {
            return UserDefaults(suiteName: "dev.rivetdeck.native.smoke")!
        }
        return .standard
    }()
}

struct ConversationEntry: Identifiable {
    let id: String
    var role: String
    var text: String
}
struct NativeSession: Identifiable {
    let id: String
    var title: String
    var workspace: String
    var status = "idle"
    var entries: [ConversationEntry] = []
    var evicted = false
}

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    var runtimeState: RuntimeState = .stopped
    var sessions: [NativeSession] = []
    var selection: String?
    var error: String?
    var busy = false
    var prompt = ""
    var resumeID = ""
    var showingResume = false
    var workspaces: [String]
    var workspace: String { didSet { UIPreferences.store.set(workspace, forKey: "workspace") } }
    var nodePath: String { didSet { UIPreferences.store.set(nodePath, forKey: "node") } }
    var runtimePath: String { didSet { UIPreferences.store.set(runtimePath, forKey: "runtime") } }
    var homePath: String { didSet { UIPreferences.store.set(homePath, forKey: "home") } }
    var provider: String { didSet { UIPreferences.store.set(provider, forKey: "provider") } }
    var model: String { didSet { UIPreferences.store.set(model, forKey: "model") } }
    var logs: [String] = []
    @ObservationIgnored private let client: any DSHClient = SDKClient()
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var operation = false
    @ObservationIgnored private var activityToken: NSObjectProtocol?
    @ObservationIgnored private var runningIDs: Set<String> = []
    @ObservationIgnored private var smokeTask: Task<Void, Never>?
    @ObservationIgnored private var smokeFailureWaiter: CheckedContinuation<Void, Never>?
    var connected: Bool { if case .connected = runtimeState { true } else { false } }
    var selected: NativeSession? { sessions.first { $0.id == selection } }
    var activeCount: Int { sessions.filter { $0.status == "running" }.count }

    private init() {
        let defaults = UIPreferences.store, environment = ProcessInfo.processInfo.environment
        let cwd = FileManager.default.currentDirectoryPath
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("runtime").path
        let candidates = [environment["RIVETDECK_NODE"], Bundle.main.resourceURL?.appendingPathComponent("node/bin/node").path,
                          "/opt/homebrew/bin/node", "/usr/local/bin/node"] .compactMap { $0 }
        let nvm = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? []
        nodePath = defaults.string(forKey: "node") ?? (candidates + versions.sorted { $0.lastPathComponent > $1.lastPathComponent }.map { $0.appendingPathComponent("bin/node").path }).first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
        runtimePath = defaults.string(forKey: "runtime") ?? environment["RIVETDECK_RUNTIME_ROOT"] ?? (bundled.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } ?? cwd + "/runtime")
        workspace = defaults.string(forKey: "workspace") ?? ""
        workspaces = defaults.stringArray(forKey: "recentWorkspaces") ?? []
        homePath = defaults.string(forKey: "home") ?? RuntimeConfiguration.defaultHome.path
        provider = defaults.string(forKey: "provider") ?? "deepseek-official"
        model = defaults.string(forKey: "model") ?? "deepseek-flash"
    }
    func observe() {
        guard observation == nil else { return }
        observation = Task { [weak self, client] in
            let stream = await client.events()
            do { for try await event in stream { self?.apply(event) } }
            catch { self?.error = error.localizedDescription; self?.runtimeState = .failed(error.localizedDescription) }
            self?.observation = nil
        }
    }
    private func apply(_ event: DSHEvent) {
        switch event {
        case .connection(let state):
            runtimeState = state; log("Runtime: \(state.label)")
            if case .failed(let message) = state { error = message }
            if case .stopped = state { markInterrupted() }
            if case .failed = state { markInterrupted() }
        case .session(let id, _, let update):
            if case .status(let status) = update {
                if status == "running" { runningIDs.insert(id) } else { runningIDs.remove(id) }
            }
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { updateActivity(); return }
            switch update {
            case .status(let status): sessions[index].status = status
            case .message(let messageID, let role, let text):
                if let existing = sessions[index].entries.firstIndex(where: { $0.id == messageID }) {
                    sessions[index].entries[existing] = ConversationEntry(id: messageID, role: role, text: text)
                } else { append(index, role: role, text: text, id: messageID) }
            case .activity(let text): append(index, role: "activity", text: text)
            case .failure(let text):
                append(index, role: "error", text: text); error = text
                smokeFailureWaiter?.resume(); smokeFailureWaiter = nil
            }
        }
        updateActivity()
    }
    private func updateActivity() {
        let starting: Bool
        if case .starting = runtimeState { starting = true } else { starting = false }
        if starting || !runningIDs.isEmpty {
            if activityToken == nil {
                activityToken = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "DeepSeek Harness is connecting or running an Agent")
            }
        } else if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token); activityToken = nil
        }
    }
    private func markInterrupted() {
        runningIDs.removeAll()
        for index in sessions.indices where sessions[index].status == "running" { sessions[index].status = "interrupted" }
    }
    private func append(_ index: Int, role: String, text: String, id: String = UUID().uuidString) {
        sessions[index].entries.append(ConversationEntry(id: id, role: role, text: text))
        if sessions[index].entries.count > 200 {
            sessions[index].entries.removeFirst(sessions[index].entries.count - 200)
            sessions[index].evicted = true
        }
    }
    private func log(_ text: String) { logs.append(text); if logs.count > 100 { logs.removeFirst(logs.count - 100) } }
    func configuration(key: String?) -> RuntimeConfiguration {
        RuntimeConfiguration(node: URL(fileURLWithPath: nodePath), runtimeRoot: URL(fileURLWithPath: runtimePath), home: URL(fileURLWithPath: homePath), workspace: URL(fileURLWithPath: workspace), provider: provider, model: model, credential: key)
    }
    func connect() async {
        guard !operation else { return }; operation = true; busy = true
        observe()
        defer { operation = false; busy = false }
        error = nil
        guard !workspace.isEmpty else { error = "Choose a workspace before connecting."; return }
        do {
            // Reconnection releases UI projections; known DSH sessions can be reopened by ID.
            await client.disconnect(); sessions = []; selection = nil
            let key = try CredentialStore.load()
            try await client.connect(configuration: configuration(key: key))
            runtimeState = .connected("SDK")
            await newSession()
        } catch { self.error = error.localizedDescription }
    }
    func shutdown() async {
        await client.disconnect()
        runningIDs.removeAll(); runtimeState = .stopped; updateActivity()
    }
    func newSession() async {
        guard connected, sessions.count < 16 else { return }
        let id = "native-" + UUID().uuidString.lowercased()
        sessions.insert(NativeSession(id: id, title: "New Session", workspace: workspace), at: 0)
        selection = id
        do { let cwd = try await client.createSession(id: id); if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].workspace = cwd } }
        catch { self.error = error.localizedDescription; sessions.removeAll { $0.id == id }; if selection == id { selection = sessions.first?.id } }
    }
    func resume() async {
        guard connected, sessions.count < 16 else { return }
        let id = resumeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessions.contains(where: { $0.id == id }) else { selection = id; showingResume = false; return }
        sessions.insert(NativeSession(id: id, title: "Resumed · \(id.prefix(14))", workspace: workspace), at: 0)
        do {
            try await client.resumeSession(id: id)
            let cwd = try await client.workingDirectory(id: id, path: nil)
            if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].workspace = cwd }
            selection = id; showingResume = false; resumeID = ""
        } catch { sessions.removeAll { $0.id == id }; self.error = error.localizedDescription }
    }
    func send() async {
        guard let id = selection, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !busy else { return }
        let text = prompt; prompt = ""; busy = true
        defer { busy = false }
        do {
            _ = try await client.prompt(sessionID: id, text: text)
            if let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].title == "New Session" {
                sessions[index].title = String(text.prefix(44))
            }
        } catch { prompt = text; self.error = error.localizedDescription }
    }
    func chooseWorkspace() {
        guard !connected, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Open Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace = url.resolvingSymlinksInPath().path
        workspaces.removeAll { $0 == workspace }; workspaces.insert(workspace, at: 0)
        workspaces = Array(workspaces.prefix(12)); UIPreferences.store.set(workspaces, forKey: "recentWorkspaces")
    }
    #if DEBUG
    func startSmokeTest(arguments: [String]) {
        guard smokeTask == nil else { return }
        // Application-owned task: SwiftUI view updates must not cancel the integration run.
        smokeTask = Task { await smokeTest(arguments: arguments) }
    }
    private func smokeTest(arguments: [String]) async {
        guard arguments.count == 8 else { return }
        let destination = URL(fileURLWithPath: arguments[2])
        try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: destination.path + ".pid", atomically: true, encoding: .utf8)
        var result: [String: Any] = ["nativeWindowCount": NSApp.windows.filter { $0.contentView != nil && !$0.isSheet }.count, "mock": false, "credentialsSupplied": false, "modelAnswerVerified": false]
        do {
            nodePath = arguments[3]; runtimePath = arguments[4]; homePath = arguments[5]; workspace = arguments[6]
            provider = "deepseek-official"; model = "deepseek-flash"
            // No Keychain lookup and no ambient API credentials in the keyless app smoke run.
            try await client.connect(configuration: configuration(key: nil)); result["handshake"] = true
            let id = "smoke-" + UUID().uuidString.lowercased()
            sessions = [NativeSession(id: id, title: "Native App Smoke Test", workspace: workspace)]; selection = id
            _ = try await client.createSession(id: id)
            result["receipt"] = try await client.prompt(sessionID: id, text: "Reply briefly.")
            try await client.wait(sessionID: id)
            if error?.contains("MISSING_CREDENTIAL") != true {
                await withCheckedContinuation { smokeFailureWaiter = $0 }
            }
            result["session"] = id
            result["missingCredentialRendered"] = error?.contains("MISSING_CREDENTIAL") == true
            result["liveRowCount"] = selected?.entries.count ?? 0
        } catch { result["error"] = error.localizedDescription }
        await shutdown()
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
        if arguments[7] == "quit" {
            // NSApplication may enter a nested termination loop. Release this MainActor
            // task first so the delegate's asynchronous shutdown task can execute.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
    #endif
}
