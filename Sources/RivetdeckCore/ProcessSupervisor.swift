import Foundation
import Darwin

public enum ProcessOutput: Sendable { case stdout(Data), eof, exited(Int32), ioFailure }

/// One immutable process generation. Pipe reads/writes each have their own serial worker;
/// the Foundation process is only signalled through this owner. No I/O runs on MainActor.
public final class ProcessSupervisor: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), diagnostics = Pipe()
    private let writer = DispatchQueue(label: "rivetdeck.runtime.write")
    private let continuation: AsyncStream<ProcessOutput>.Continuation
    public let outputEvents: AsyncStream<ProcessOutput>
    private let lock = NSLock()
    private var stderrByteCount = 0
    private var processGroup: Int32 = 0

    public init() {
        let pair = AsyncStream<ProcessOutput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        outputEvents = pair.stream; continuation = pair.continuation
    }
    public func start(executable: URL, arguments: [String], directory: URL, environment: [String: String]) throws {
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = directory; process.environment = environment
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input; process.standardOutput = output; process.standardError = diagnostics
        // Exit follows all stdout bytes because the reader drains to EOF before waiting.
        try process.run()
        let pid = process.processIdentifier
        if getpgid(pid) == pid { processGroup = pid }
        DispatchQueue(label: "rivetdeck.runtime.stdout").async { [self] in
            while true {
                let bytes = output.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                if case .dropped = continuation.yield(.stdout(bytes)) { forceStop(); break }
            }
            continuation.yield(.eof)
            process.waitUntilExit()
            continuation.yield(.exited(process.terminationStatus)); continuation.finish()
            try? output.fileHandleForReading.close()
        }
        DispatchQueue(label: "rivetdeck.runtime.stderr").async { [self] in
            // Drain stderr, retain only a count: arbitrary plugins may print credentials.
            while true {
                let bytes = diagnostics.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                lock.withLock { stderrByteCount = min(Int.max - 65536, stderrByteCount) + bytes.count }
            }
            try? diagnostics.fileHandleForReading.close()
        }
    }
    public func write(_ bytes: Data) async throws {
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            writer.async { [self] in
                do { try input.fileHandleForWriting.write(contentsOf: bytes); waiter.resume() }
                catch { waiter.resume(throwing: ClientError.transport("Runtime pipe write failed")) }
            }
        }
    }
    public var diagnosticBytes: Int { lock.withLock { stderrByteCount } }
    public var isRunning: Bool { process.isRunning }
    public func stop(graceful: Bool = false) async {
        // A deadline here bounds teardown, never readiness. SDK shutdown precedes this call.
        if graceful {
            for _ in 0..<100 {
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        if process.isRunning {
            process.terminate()
            for _ in 0..<40 {
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        if process.isRunning {
            forceStop()
            for _ in 0..<20 {
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        writer.async { [self] in try? input.fileHandleForWriting.close() }
    }
    public func forceStop() {
        guard process.isRunning else { return }
        if processGroup > 0 { _ = kill(-processGroup, SIGKILL) }
        else if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
}
