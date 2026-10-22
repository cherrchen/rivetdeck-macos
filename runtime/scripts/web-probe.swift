import Foundation

// Feasibility probe: URLSession can access authenticated unary RPC and WebSocket streams
// without Cordis/TypeScript in the client. Credentials enter only through stdin.
@main struct WebProbe {
    static func main() async throws {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let config = try JSONSerialization.jsonObject(with: input) as! [String: String]
        let origin = config["origin"]!, cookie = config["cookie"]!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: origin + "/api/session/list")!)
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["type": "client-request", "rpcId": "swift-list", "method": "session/list", "payload": ["args": ["_request": [:]]]])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (result["result"] as? [String: Any])?["ok"] as? Bool == true else { throw URLError(.badServerResponse) }
        FileHandle.standardOutput.write(Data("Swift URLSession: authenticated session/list succeeded\n".utf8))
        var socketRequest = URLRequest(url: URL(string: origin.replacingOccurrences(of: "http:", with: "ws:") + "/api/remote.mux")!)
        socketRequest.setValue(cookie, forHTTPHeaderField: "Cookie"); socketRequest.timeoutInterval = 10
        let socket = session.webSocketTask(with: socketRequest); socket.resume()
        let open: [String: Any] = ["type": "open", "streamId": "swift-events", "endpoint": "$events", "payload": ["args": [:]]]
        try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: open), as: UTF8.self)))
        let received = try await socket.receive()
        if case .string(let frameText) = received,
           let metadata = try JSONSerialization.jsonObject(with: Data(frameText.utf8)) as? [String: Any] {
            let summary = "WebSocket first frame: type=\(metadata["type"] ?? "none"), valueType=\((metadata["value"] as? [String: Any])?["type"] ?? "none"), errorCode=\((metadata["error"] as? [String: Any])?["code"] ?? "none")\n"
            FileHandle.standardOutput.write(Data(summary.utf8))
        }
        guard case .string(let text) = received,
              let frame = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              frame["type"] as? String == "item",
              (frame["value"] as? [String: Any])?["type"] as? String == "ready" else { throw URLError(.cannotParseResponse) }
        print("Swift URLSession WebSocket: $events ready received")
        try await socket.send(.string("{\"type\":\"cancel\",\"streamId\":\"swift-events\"}"))
        socket.cancel(with: .normalClosure, reason: nil)
    }
}
