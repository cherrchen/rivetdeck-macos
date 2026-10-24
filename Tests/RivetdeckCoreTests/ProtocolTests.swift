import XCTest
@testable import RivetdeckCore

final class ProtocolTests: XCTestCase {
    func testSplitUTF8AndMultipleFrames() throws {
        let bytes = Data("{\"text\":\"中文🛠\"}\n{}\n".utf8)
        var framer = LineFramer(), frames: [Data] = []
        for byte in bytes { frames += try framer.append(Data([byte])) }
        XCTAssertEqual(frames.count, 2)
        let message = try JSONDecoder().decode(JSONValue.self, from: frames[0])
        XCTAssertEqual(message["text"].string, "中文🛠")
        try framer.finish()
    }
    func testFramingLimitsAndTruncatedEOF() throws {
        var framer = LineFramer(maximumBytes: 5)
        XCTAssertThrowsError(try framer.append(Data("123456".utf8)))
        var closed = LineFramer()
        _ = try closed.append(Data("{\"a\":".utf8))
        XCTAssertThrowsError(try closed.finish())
        var large = LineFramer(maximumBytes: 3)
        XCTAssertThrowsError(try large.append(Data("abcd\n".utf8)))
    }
    func testResponseAndRPCError() throws {
        let frame = try JSONDecoder().decode(RPCFrame.self, from: Data("{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"error\":{\"code\":-32603,\"message\":\"missing\"}}".utf8))
        XCTAssertEqual(frame.error?.code, -32603)
        XCTAssertEqual(frame.id?.string, "1")
    }
    func testMessageToolFailureAndUnknownEventProjection() throws {
        let decoder = EventDecoder()
        let samples: [(String, String, SessionUpdate)] = [
            ("assistant/message", "{\"message\":{\"id\":\"m\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}}", .message(id: "m", role: "assistant", text: "hello")),
            ("tool/call", "{\"name\":\"bash\"}", .activity(.toolCall(name: "bash"))),
            ("turn/end", "{\"reason\":{\"kind\":\"error\",\"error\":{\"code\":\"MISSING_CREDENTIAL\",\"message\":\"secret\"}}}", .failure("Agent failed (MISSING_CREDENTIAL). Check DSH configuration and credentials.")),
            ("turn/end", "{\"reason\":{\"kind\":\"stop\"}}", .activity(.turnEnded(reason: "stop"))),
            ("approval/request", "{}", .activity(.approval(type: "approval/request"))),
            ("new-plugin/event", "{}", .activity(.other(type: "new-plugin/event")))
        ]
        for (type, data, update) in samples {
            let input = Data("{\"sessionId\":\"a\",\"event\":{\"type\":\"\(type)\",\"seq\":1,\"data\":\(data)}}".utf8)
            let params = try JSONDecoder().decode(JSONValue.self, from: input)
            XCTAssertEqual(try decoder.decode(method: "session.event", params: params), .session(id: "a", sequence: 1, update: update))
        }
        XCTAssertThrowsError(try decoder.decode(method: "session.status", params: .object([:])))
    }
    func testActivitySummariesMatchLegacyStrings() throws {
        let decoder = EventDecoder()
        XCTAssertEqual(Activity.toolCall(name: "bash").summary, "Tool: bash")
        XCTAssertEqual(Activity.turnEnded(reason: "stop").summary, "Turn ended: stop")
        XCTAssertEqual(Activity.approval(type: "approval/request").summary, "approval/request — SDK cannot answer approval requests")
        XCTAssertEqual(Activity.other(type: "new-plugin/event").summary, "new-plugin/event")
        let started = try decoder.decode(method: "subagent.started", params: .object(["parentSessionId": .string("p"), "childSessionId": .string("c")]))
        XCTAssertEqual(started, .session(id: "p", sequence: nil, update: .activity(.subagentStarted(id: "c"))))
        if case .session(_, _, .activity(let activity)) = started {
            XCTAssertEqual(activity.summary, "Subagent started: c")
        }
        let finished = try decoder.decode(method: "subagent.finished", params: .object(["parentSessionId": .string("p"), "status": .string("ok")]))
        XCTAssertEqual(finished, .session(id: "p", sequence: nil, update: .activity(.subagentFinished(status: "ok"))))
        if case .session(_, _, .activity(let activity)) = finished {
            XCTAssertEqual(activity.summary, "Subagent finished: ok")
        }
    }
    func testEnvironmentDoesNotInheritPolicyOrAmbientSecrets() {
        let config = RuntimeConfiguration(node: URL(fileURLWithPath: "/usr/bin/true"), runtimeRoot: URL(fileURLWithPath: "/tmp"), home: URL(fileURLWithPath: "/tmp/isolated"), workspace: URL(fileURLWithPath: "/tmp"))
        XCTAssertNil(config.environment["NODE_OPTIONS"])
        XCTAssertNil(config.environment["DSH_PERMISSION_MODE"])
        XCTAssertNil(config.environment["DEEPSEEK_API_KEY"])
        XCTAssertEqual(config.environment["DSH_HOME"], "/tmp/isolated")
    }
}
