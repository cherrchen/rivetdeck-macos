import Foundation

public actor SDKClient: DSHClient {
    private var supervisor: ProcessSupervisor?
    private var reader: Task<Void, Never>?
    private var generation = UUID()
    private var framer = LineFramer()
    private struct Pending: Sendable {
        var waiter: CheckedContinuation<JSONValue, Error>
        var timeout: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    private var observers: [UUID: AsyncThrowingStream<DSHEvent, Error>.Continuation] = [:]
    private var sequences: [String: Int] = [:]
    private var closing = false
    private var ready = false
    private var secret: String?
    private let requestTimeout: Duration
    private let handshakeTimeout: Duration
    public init(requestTimeout: Duration = .seconds(15), handshakeTimeout: Duration = .seconds(30)) {
        self.requestTimeout = requestTimeout; self.handshakeTimeout = handshakeTimeout
    }

    deinit {
        reader?.cancel(); supervisor?.forceStop()
        for entry in pending.values {
            entry.timeout.cancel(); entry.waiter.resume(throwing: ClientError.transport("Client released"))
        }
        for continuation in observers.values { continuation.finish() }
    }

    public func events() -> AsyncThrowingStream<DSHEvent, Error> {
        let id = UUID()
        let pair = AsyncThrowingStream<DSHEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(512))
        observers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return pair.stream
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func publish(_ event: DSHEvent) {
        var overflow: [UUID] = []
        for (id, continuation) in observers {
            if case .dropped = continuation.yield(event) { overflow.append(id) }
        }
        for id in overflow {
            observers.removeValue(forKey: id)?.finish(throwing: ClientError.transport("Live event consumer exceeded its buffer. Reconnect; SDK cannot replay missed events."))
        }
        if !overflow.isEmpty, !closing { Task { await self.disconnect() } }
    }
    public func connect(configuration: RuntimeConfiguration) async throws {
        guard supervisor == nil else { throw ClientError.transport("Disconnect the current runtime before reconnecting.") }
        try configuration.validate()
        closing = false; ready = false; framer = LineFramer(); sequences = [:]; secret = configuration.credential
        publish(.connection(.starting))
        let process = ProcessSupervisor(), token = UUID()
        generation = token
        do {
            try process.start(executable: configuration.node, arguments: [configuration.entry.path, "--profile", "sdk"], directory: configuration.workspace, environment: configuration.environment)
            supervisor = process
            reader = Task { [weak self] in
                for await output in process.outputEvents {
                    guard !Task.isCancelled else { break }
                    await self?.receive(output, generation: token)
                }
            }
            let result = try await request("initialize", params: .object([
                "cwd": .string(configuration.workspace.resolvingSymlinksInPath().path),
                "provider": .string(configuration.provider), "model": .string(configuration.model)
            ]), timeout: handshakeTimeout)
            guard result["serverInfo"]["name"].string == "deepseek-harness-sdk-runtime" else {
                throw ClientError.protocolViolation("Unexpected SDK server identity")
            }
            guard generation == token, !closing else { throw ClientError.transport("Connection was closed during initialization") }
            ready = true
            publish(.connection(.connected(result["serverInfo"]["version"].string ?? "unknown")))
        } catch {
            await process.stop()
            if generation == token {
                supervisor = nil; ready = false; secret = nil
                publish(.connection(.failed(sanitized(error.localizedDescription))))
            }
            throw error
        }
    }
    public func createSession(id: String) async throws -> String { try await workingDirectory(id: id, path: nil) }
    public func resumeSession(id: String) async throws {
        try requireReady(id)
        _ = try await request("session/resume", params: .object(["sessionId": .string(id)]))
    }
    public func workingDirectory(id: String, path: String?) async throws -> String {
        try requireReady(id)
        var params: [String: JSONValue] = ["sessionId": .string(id)]
        if let path { params["path"] = .string(path) }
        let result = try await request(path == nil ? "session/working-directory/get" : "session/working-directory/set", params: .object(params))
        guard let cwd = result["cwd"].string else { throw ClientError.protocolViolation("SDK returned no working directory") }
        return cwd
    }
    public func prompt(sessionID: String, text: String) async throws -> String {
        try requireReady(sessionID)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 262144 else {
            throw ClientError.invalidConfiguration("Prompt must contain 1–262144 UTF-8 bytes.")
        }
        let result = try await request("session/prompt", params: .object([
            "sessionId": .string(sessionID), "contentBlocks": .array([.object(["type": .string("text"), "text": .string(text)])])
        ]))
        guard let id = result["messageId"].string else { throw ClientError.protocolViolation("SDK returned no prompt receipt") }
        return id
    }
    public func wait(sessionID: String) async throws {
        try requireReady(sessionID)
        _ = try await request("session/wait", params: .object(["sessionId": .string(sessionID)]), timeout: .seconds(300))
    }
    private func requireReady(_ sessionID: String) throws {
        guard ready, !closing else { throw ClientError.transport("Runtime is not connected") }
        guard !sessionID.isEmpty, sessionID.utf8.count <= 200,
              sessionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw ClientError.invalidConfiguration("Session IDs must be 1–200 ASCII letters, digits, hyphens or underscores.")
        }
    }
    private func request(_ method: String, params: JSONValue = .object([:]), timeout: Duration? = nil) async throws -> JSONValue {
        try Task.checkCancellation()
        guard let process = supervisor, process.isRunning, pending.count < 64 else {
            throw ClientError.transport("Runtime unavailable or request limit exceeded")
        }
        let id = UUID().uuidString
        var bytes = try JSONEncoder().encode(RPCFrame(id: id, method: method, params: params)); bytes.append(10)
        let encoded = bytes
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiter in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: timeout ?? self?.requestTimeout ?? .seconds(15)) } catch { return }
                    await self?.reject(id, error: ClientError.timeout(method))
                }
                pending[id] = Pending(waiter: waiter, timeout: timer)
                Task { [weak self] in
                    do { try await process.write(encoded) }
                    catch { await self?.reject(id, error: error) }
                }
            }
        } onCancel: { Task { await self.reject(id, error: CancellationError()) } }
    }
    private func reject(_ id: String, error: Error) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout.cancel(); entry.waiter.resume(throwing: error)
    }
    private func failPending(_ error: Error) { for id in Array(pending.keys) { reject(id, error: error) } }
    private func sanitized(_ text: String) -> String {
        var value = text
        if let secret, !secret.isEmpty { value = value.replacingOccurrences(of: secret, with: "[redacted]") }
        value = value.replacingOccurrences(of: "(?i)(bearer\\s+|(?:token|api[_-]?key)[=:]\\s*)[^\\s,;]+", with: "$1[redacted]", options: .regularExpression)
        return String(value.prefix(2048))
    }
    private func receive(_ output: ProcessOutput, generation token: UUID) async {
        guard generation == token else { return }
        do {
            switch output {
            case .stdout(let data):
                for line in try framer.append(data) {
                    let frame = try JSONDecoder().decode(RPCFrame.self, from: line)
                    guard frame.jsonrpc == "2.0" else { throw ClientError.protocolViolation("Invalid JSON-RPC version") }
                    if let id = frame.id?.string {
                        guard frame.method == nil else { throw ClientError.protocolViolation("SDK sent an unsupported request") }
                        if let failure = frame.error { reject(id, error: ClientError.rpc(failure.code, sanitized(failure.message))) }
                        else if let entry = pending.removeValue(forKey: id) {
                            entry.timeout.cancel(); entry.waiter.resume(returning: frame.result ?? .null)
                        }
                    } else if let method = frame.method {
                        if let event = try EventDecoder().decode(method: method, params: frame.params ?? .null) {
                            if case .session(let id, let sequence?, _) = event {
                                guard sequences.count < 128 || sequences[id] != nil else { throw ClientError.protocolViolation("Too many live sessions; restart runtime") }
                                if let previous = sequences[id], sequence <= previous { throw ClientError.protocolViolation("Out-of-order session event") }
                                sequences[id] = sequence
                            }
                            publish(event)
                        }
                    }
                }
            case .eof:
                try framer.finish()
                if !closing { throw ClientError.transport("Runtime stdout closed unexpectedly") }
            case .ioFailure: throw ClientError.transport("Runtime pipe read failed")
            case .exited(let code):
                let count = supervisor?.diagnosticBytes ?? 0
                ready = false
                failPending(ClientError.transport("Runtime exited (\(code))"))
                if !closing { publish(.connection(.failed("Runtime exited (\(code)); stderr drained: \(count) bytes. Raw stderr is withheld to protect credentials."))) }
                supervisor = nil
            }
        } catch {
            ready = false; failPending(error)
            if !closing { publish(.connection(.failed(sanitized(error.localizedDescription)))) }
            await supervisor?.stop()
        }
    }
    public func disconnect() async {
        guard !closing else { return }
        closing = true; ready = false
        let token = generation, process = supervisor
        if let process, process.isRunning { _ = try? await request("shutdown", timeout: .seconds(5)) }
        await process?.stop(graceful: true)
        if generation == token {
            failPending(ClientError.transport("Runtime disconnected"))
            reader?.cancel(); reader = nil; supervisor = nil; sequences = [:]; secret = nil
            publish(.connection(.stopped))
        }
        closing = false
    }
}
