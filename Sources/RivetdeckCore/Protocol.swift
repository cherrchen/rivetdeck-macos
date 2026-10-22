import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .object(let v): try box.encode(v)
        case .array(let v): try box.encode(v)
        case .string(let v): try box.encode(v)
        case .number(let v): try box.encode(v)
        case .bool(let v): try box.encode(v)
        case .null: try box.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let value) = self { return value[key] ?? .null }; return .null }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var array: [JSONValue] { if case .array(let value) = self { value } else { [] } }
    public var integer: Int? { if case .number(let value) = self, value.isFinite, value >= 0, value < Double(Int.max), value.rounded() == value { return Int(value) }; return nil }
}

public enum ClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String), transport(String), protocolViolation(String), timeout(String), rpc(Int, String)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let s), .transport(let s), .protocolViolation(let s): s
        case .timeout(let s): "Timed out waiting for \(s). The runtime may still be working."
        case .rpc(let code, let message): "DSH (\(code)): \(message)"
        }
    }
}

/// Byte framing preserves UTF-8 split across Pipe reads. No newline-free input can grow without bound.
public struct LineFramer: Sendable {
    private var buffer = Data()
    public let maximumBytes: Int
    public init(maximumBytes: Int = 8 * 1024 * 1024) { self.maximumBytes = maximumBytes }
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            guard buffer.distance(from: buffer.startIndex, to: newline) <= maximumBytes else {
                throw ClientError.protocolViolation("SDK frame exceeds size limit")
            }
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if !line.isEmpty { frames.append(line) }
        }
        guard buffer.count <= maximumBytes else { throw ClientError.protocolViolation("SDK frame exceeds size limit") }
        return frames
    }
    public func finish() throws {
        if !buffer.isEmpty { throw ClientError.protocolViolation("SDK closed with a truncated frame") }
    }
}

public struct RPCFrame: Codable, Sendable {
    public var jsonrpc: String
    public var id: JSONValue?
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: RPCFailure?
    public struct RPCFailure: Codable, Sendable { public var code: Int; public var message: String }
    public init(id: String, method: String, params: JSONValue) {
        self.jsonrpc = "2.0"; self.id = .string(id); self.method = method; self.params = params
    }
}

public enum RuntimeState: Sendable, Equatable {
    case stopped, starting, connected(String), failed(String)
    public var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Connecting…"
        case .connected: "Connected"
        case .failed: "Disconnected"
        }
    }
}
public enum SessionUpdate: Sendable, Equatable {
    case status(String)
    case message(id: String, role: String, text: String)
    case activity(String)
    case failure(String)
}
public enum DSHEvent: Sendable, Equatable {
    case connection(RuntimeState)
    case session(id: String, sequence: Int?, update: SessionUpdate)
}

/// A live presentation projection, never a replacement for DSH's persisted session log.
public struct EventDecoder: Sendable {
    public init() {}
    public func decode(method: String, params: JSONValue) throws -> DSHEvent? {
        if method == "session.status" {
            guard let id = params["sessionId"].string, let status = params["status"].string,
                  ["idle", "running"].contains(status) else { throw ClientError.protocolViolation("Invalid session.status") }
            return .session(id: id, sequence: nil, update: .status(status))
        }
        if method == "subagent.started", let parent = params["parentSessionId"].string {
            return .session(id: parent, sequence: nil, update: .activity("Subagent started: \(params["childSessionId"].string ?? "unknown")"))
        }
        if method == "subagent.finished", let parent = params["parentSessionId"].string {
            return .session(id: parent, sequence: nil, update: .activity("Subagent finished: \(params["status"].string ?? "unknown")"))
        }
        guard method == "session.event" else { return nil }
        let event = params["event"], data = event["data"]
        guard let id = params["sessionId"].string, let type = event["type"].string, let sequence = event["seq"].integer else {
            throw ClientError.protocolViolation("Invalid session.event envelope")
        }
        let update: SessionUpdate
        switch type {
        case "user/message", "assistant/message", "tool/result":
            let message = type == "user/message" ? data : data["message"]
            var role = message["role"].string ?? (type == "user/message" ? "user" : "assistant")
            if role == "user", let source = message["source"]["kind"].string, source != "user" { role = "context" }
            let text = message["content"].array.compactMap { block -> String? in
                block["text"].string ?? (block["type"].string.map { "[\($0)]" })
            }.joined(separator: "\n")
            update = .message(id: message["id"].string ?? "event-\(sequence)", role: role, text: String(text.prefix(32768)) + (text.count > 32768 ? "\n[Message truncated in this live view]" : ""))
        case "tool/call": update = .activity("Tool: \(data["name"].string ?? "unknown")")
        case "turn/end":
            let reason = data["reason"]
            if reason["kind"].string == "error" {
                // Do not echo arbitrary provider response bodies, headers, or credentials.
                update = .failure("Agent failed (\(reason["error"]["code"].string ?? "UNKNOWN")). Check DSH configuration and credentials.")
            } else { update = .activity("Turn ended: \(reason["kind"].string ?? "unknown")") }
        case "approval/request", "approval/decision": update = .activity("\(type) — SDK cannot answer approval requests")
        default: update = .activity(type)
        }
        return .session(id: id, sequence: sequence, update: update)
    }
}
