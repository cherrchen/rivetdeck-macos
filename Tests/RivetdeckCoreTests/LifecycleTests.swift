import XCTest
@testable import RivetdeckCore

private actor CollectedEvents {
    var values: [DSHEvent] = []
    func append(_ value: DSHEvent) { values.append(value) }
    func snapshot() -> [DSHEvent] { values }
}

final class LifecycleTests: XCTestCase, @unchecked Sendable {
    private func fixture(_ mode: String = "normal") throws -> (RuntimeConfiguration, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rivetdeck-test-" + UUID().uuidString)
        let entry = root.appendingPathComponent("runtime/node_modules/@deepseek-ai/dsh/lib/bin.js")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = try XCTUnwrap(Bundle.module.url(forResource: "fake_runtime", withExtension: "py", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: source, to: entry)
        for package in ["dsh", "dsh-sdk-protocol"] {
            let metadata = root.appendingPathComponent("runtime/node_modules/@deepseek-ai/\(package)/package.json")
            try FileManager.default.createDirectory(at: metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"version\":\"0.2.1-rc.2\"}".utf8).write(to: metadata)
        }
        try Data(mode.utf8).write(to: root.appendingPathComponent("fixture-mode"))
        return (RuntimeConfiguration(node: URL(fileURLWithPath: "/usr/bin/python3"), runtimeRoot: root.appendingPathComponent("runtime"), home: root.appendingPathComponent("home"), workspace: root), root)
    }
    func testLifecycleAndSessionIsolation() async throws {
        let (config, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let client = SDKClient()
        try await client.connect(configuration: config)
        _ = try await client.createSession(id: "a")
        _ = try await client.createSession(id: "b")
        let changed = try await client.workingDirectory(id: "a", path: "/tmp")
        let unchanged = try await client.workingDirectory(id: "b", path: nil)
        XCTAssertEqual(changed, "/tmp"); XCTAssertEqual(URL(fileURLWithPath: unchanged).resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
        async let a = client.prompt(sessionID: "a", text: "one")
        async let b = client.prompt(sessionID: "b", text: "two")
        let receipts = try await [a, b]
        XCTAssertEqual(Set(receipts), Set(["a-message", "b-message"]))
        await client.disconnect()
        try await client.connect(configuration: config)
        await client.disconnect()
    }
    func testSessionEventRoutingAndOrder() async throws {
        let (config, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let client = SDKClient(), collected = CollectedEvents()
        let events = await client.events()
        let stopped = expectation(description: "Ordered stopped event")
        let listener = Task {
            for try await event in events {
                await collected.append(event)
                if event == .connection(.stopped) { stopped.fulfill() }
            }
        }
        try await client.connect(configuration: config)
        _ = try await client.prompt(sessionID: "a", text: "one")
        _ = try await client.prompt(sessionID: "b", text: "two")
        await client.disconnect()
        await fulfillment(of: [stopped], timeout: 2)
        listener.cancel(); _ = try? await listener.value
        let rows = await collected.snapshot().compactMap { event -> (String, SessionUpdate)? in
            if case .session(let id, _, let update) = event { return (id, update) }; return nil
        }
        for id in ["a", "b"] {
            let values = rows.filter { $0.0 == id }.map(\.1)
            XCTAssertEqual(values.count, 3)
            XCTAssertEqual(values.first, .status("running")); XCTAssertEqual(values.last, .status("idle"))
        }
    }
    func testUnexpectedExitAndDisconnectRejectPendingPrompt() async throws {
        for mode in ["crash", "disconnect"] {
            let (config, root) = try fixture(mode)
            let client = SDKClient()
            let failed = expectation(description: "Runtime reports \(mode)")
            let events = await client.events()
            let listener = Task {
                for try await event in events {
                    if case .connection(.failed) = event { failed.fulfill(); break }
                }
            }
            try await client.connect(configuration: config)
            do { _ = try await client.prompt(sessionID: "a", text: "trigger"); XCTFail("Expected \(mode)") }
            catch { XCTAssertTrue(error is ClientError) }
            await fulfillment(of: [failed], timeout: 3)
            listener.cancel(); _ = try? await listener.value
            await client.disconnect()
            try? FileManager.default.removeItem(at: root)
        }
    }
    func testHandshakeTimeoutAndMalformedStdout() async throws {
        for mode in ["timeout", "invalid"] {
            let (config, root) = try fixture(mode)
            let client = SDKClient(requestTimeout: .milliseconds(100), handshakeTimeout: .milliseconds(100))
            do { try await client.connect(configuration: config); XCTFail("Expected \(mode)") }
            catch { XCTAssertTrue(error is ClientError || error is DecodingError) }
            await client.disconnect()
            try? FileManager.default.removeItem(at: root)
        }
    }
    func testSessionIDValidationAndErrorRedaction() async throws {
        let (config, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let client = SDKClient(); try await client.connect(configuration: config)
        do { _ = try await client.createSession(id: "../escape"); XCTFail("Invalid ID accepted") } catch { }
        do { try await client.resumeSession(id: "missing"); XCTFail("Expected RPC error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("fixture-secret")) }
        await client.disconnect()
    }
    func testSupervisorForcesTerminationWhenSIGTERMIgnored() async throws {
        let process = ProcessSupervisor()
        try process.start(executable: URL(fileURLWithPath: "/bin/sh"),
                          arguments: ["-c", "trap '' TERM; printf 'ready\\n'; exec /bin/sleep 30"],
                          directory: URL(fileURLWithPath: "/tmp"), environment: ["PATH": "/usr/bin:/bin"])
        for await event in process.outputEvents {
            if case .stdout = event { break }
        }
        await process.stop()
        XCTAssertFalse(process.isRunning)
    }
    func testRealRuntimeWithoutPaidModel() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let node = env["RIVETDECK_INTEGRATION_NODE"], let runtime = env["RIVETDECK_RUNTIME_ROOT"] else {
            throw XCTSkip("Set RIVETDECK_INTEGRATION_NODE and RIVETDECK_RUNTIME_ROOT for official npm runtime validation. No API key used.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rivetdeck-real-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = RuntimeConfiguration(node: URL(fileURLWithPath: node), runtimeRoot: URL(fileURLWithPath: runtime), home: root.appendingPathComponent("home"), workspace: root)
        let client = SDKClient(); try await client.connect(configuration: config)
        let id = "integration-" + UUID().uuidString
        let cwd = try await client.createSession(id: id); XCTAssertEqual(cwd, root.path)
        _ = try await client.prompt(sessionID: id, text: "hello")
        try await client.wait(sessionID: id)
        await client.disconnect()
        try await client.connect(configuration: config)
        try await client.resumeSession(id: id)
        await client.disconnect()
    }
}
