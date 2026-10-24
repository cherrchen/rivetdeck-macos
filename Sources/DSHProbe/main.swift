import Foundation
import RivetdeckCore

@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else { print("Usage: dsh-probe NODE RUNTIME_ROOT ISOLATED_DSH_HOME [WORKSPACE] [--live]"); return }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let workspace = args.count > 4 && args[4] != "--live" ? URL(fileURLWithPath: args[4]) : root
        let live = args.contains("--live")
        let fixture = args.contains("--fixture")
        let fixtureURL = fixture ? ProcessInfo.processInfo.environment["RIVETDECK_TEST_BASE_URL"] : nil
        if fixture { guard fixtureURL?.hasPrefix("http://127.0.0.1:") == true else { throw ClientError.invalidConfiguration("Fixture must use a loopback test server") } }
        let client = SDKClient()
        let stream = await client.events()
        let collector = Task { () -> (Int, Bool) in
            var count = 0, missingCredential = false
            do {
                for try await event in stream {
                    switch event {
                    case .connection(let state):
                        print("Runtime: \(state.label)")
                        if state == .stopped { return (count, missingCredential) }
                    case .session(_, _, let update):
                        count += 1
                        switch update {
                        case .failure(let message): print(message); missingCredential = message.contains("MISSING_CREDENTIAL")
                        case .message(_, let role, let text): print("Message \(role): \((live || fixture) ? text : "[content withheld]")")
                        case .activity(let activity): print("Event: \(activity.summary)")
                        case .status(let status): print("Agent: \(status)")
                        }
                    }
                }
            } catch { print("Event stream failed: \(error.localizedDescription)") }
            return (count, missingCredential)
        }
        do {
            try await client.connect(configuration: RuntimeConfiguration(
                node: URL(fileURLWithPath: args[1]), runtimeRoot: URL(fileURLWithPath: args[2]),
                home: URL(fileURLWithPath: args[3]), workspace: workspace,
                credential: fixture ? "test-fixture-only" : (live ? ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] : nil), baseURL: fixtureURL))
            let id = "native-" + UUID().uuidString.lowercased()
            print("Session ID: \(id)")
            let cwd = try await client.createSession(id: id); print("Workspace: \(cwd)")
            let receipt = try await client.prompt(sessionID: id, text: "Reply with a short greeting.")
            print("Durable receipt: \(receipt)")
            try await client.wait(sessionID: id)
            await client.disconnect()
            try await client.connect(configuration: RuntimeConfiguration(node: URL(fileURLWithPath: args[1]), runtimeRoot: URL(fileURLWithPath: args[2]), home: URL(fileURLWithPath: args[3]), workspace: workspace))
            try await client.resumeSession(id: id)
            print("Resumed the same persisted session (history replay is not exposed by SDK)")
            await client.disconnect()
            collector.cancel()
            let evidence = await collector.value
            guard evidence.0 > 0 else { throw ClientError.protocolViolation("No session events received") }
            print("PASS: handshake, session, prompt, events, shutdown, restart, resume. Model output: \(fixture ? "deterministic TEST fixture" : (live ? "inspect above" : "no credentials supplied")). Events: \(evidence.0)")
        } catch {
            await client.disconnect(); collector.cancel(); throw error
        }
    }
}
