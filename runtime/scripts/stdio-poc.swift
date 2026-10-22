import Foundation

// M0 probe only. Production uses the asynchronous RivetdeckCore supervisor.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let runtime = root.appendingPathComponent("runtime")
let home = root.appendingPathComponent(".runtime-test/poc")
try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
let process = Process()
let input = Pipe(), output = Pipe(), diagnostics = Pipe()
process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
process.arguments = [runtime.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js").path, "--profile", "sdk"]
process.currentDirectoryURL = root
process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "DSH_HOME": home.path]
process.standardInput = input; process.standardOutput = output; process.standardError = diagnostics
var stderrBytes = 0
diagnostics.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty { FileHandle.standardError.write(data) }
}
try process.run()
DispatchQueue.global().asyncAfter(deadline: .now() + 50) { if process.isRunning { process.terminate() } }
var buffer = Data(), counter = 0, notifications = 0
func request(_ method: String, _ params: [String: Any] = [:], allowError: Bool = false) throws -> [String: Any] {
    counter += 1
    let id = counter
    let frame: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    var bytes = try JSONSerialization.data(withJSONObject: frame); bytes.append(10)
    try input.fileHandleForWriting.write(contentsOf: bytes)
    while true {
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let reply = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let event = reply["method"] as? String {
                notifications += 1
                let p = reply["params"] as? [String: Any] ?? [:]
                let detail = (p["event"] as? [String: Any])?["type"] ?? p["status"] ?? ""
                print("notification \(event) \(detail)")
            }
            if reply["id"] as? Int == id {
                if let error = reply["error"] {
                    print("\(method): error \(error)")
                    if !allowError { throw NSError(domain: method, code: 1) }
                } else { print("\(method): \(reply["result"] ?? "null")") }
                return reply
            }
        }
        let chunk = output.fileHandleForReading.availableData
        guard !chunk.isEmpty else { throw NSError(domain: "Runtime EOF", code: 2) }
        buffer.append(chunk)
    }
}
_ = try request("initialize", ["cwd": root.path, "provider": "deepseek-official", "model": "deepseek-chat"])
let session = "native-poc-" + UUID().uuidString.lowercased()
_ = try request("session/working-directory/get", ["sessionId": session])
_ = try request("session/working-directory/set", ["sessionId": session, "path": root.path])
_ = try request("session/working-directory/get", ["sessionId": "native-isolation-" + UUID().uuidString.lowercased()])
_ = try request("session/prompt", ["sessionId": session, "contentBlocks": [["type": "text", "text": "Reply briefly."]]])
_ = try request("session/wait", ["sessionId": session], allowError: true)
_ = try request("session/cancel", ["sessionId": session], allowError: true)
_ = try request("shutdown")
process.waitUntilExit()
print("exit=\(process.terminationStatus), notifications=\(notifications), session=\(session)")
if process.terminationStatus != 0 || notifications == 0 { exit(1) }
