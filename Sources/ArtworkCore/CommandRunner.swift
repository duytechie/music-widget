import Foundation
import Darwin

public enum CommandError: Error, LocalizedError {
    case timedOut
    case failed(Int32, String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "Music took too long to respond."
        case .cancelled: return "The request was cancelled."
        case let .failed(_, message): return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public var isPermissionDenied: Bool {
        guard case let .failed(_, message) = self else { return false }
        return message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized to send apple events")
    }
}

/// Every invocation is bounded, drains both pipes, and kills its own child on cancellation.
/// The caller awaits each invocation before starting the next Music request.
public enum CommandRunner {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Data {
        let command = CommandExecution(executable: executable, arguments: arguments, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                command.start(continuation)
            }
        } onCancel: {
            command.cancel()
        }
    }
}

private final class CommandExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private let timeout: TimeInterval
    private var cancelled = false
    private var expired = false
    private var completed = false

    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<Data, Error>) {
        DispatchQueue.global(qos: .utility).async { [self] in
            lock.lock()
            if cancelled {
                completed = true
                lock.unlock()
                continuation.resume(throwing: CommandError.cancelled)
                return
            }
            do {
                try process.run()
            } catch {
                completed = true
                lock.unlock()
                continuation.resume(throwing: error)
                return
            }
            lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [self] in
                lock.lock()
                if !completed && process.isRunning {
                    expired = true
                    process.terminate()
                    scheduleKill()
                }
                lock.unlock()
            }

            // Drain stderr concurrently so a verbose child cannot fill a pipe and deadlock.
            let stderr = DataBox()
            let drained = DispatchGroup()
            drained.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                stderr.value = errors.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            drained.wait()
            lock.lock()
            completed = true
            let wasCancelled = cancelled
            let wasExpired = expired
            lock.unlock()
            if wasCancelled {
                continuation.resume(throwing: CommandError.cancelled)
            } else if wasExpired {
                continuation.resume(throwing: CommandError.timedOut)
            } else if process.terminationStatus != 0 {
                continuation.resume(throwing: CommandError.failed(process.terminationStatus, String(decoding: stderr.value, as: UTF8.self)))
            } else {
                continuation.resume(returning: stdout)
            }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        if !completed && process.isRunning {
            process.terminate()
            scheduleKill()
        }
        lock.unlock()
    }

    private func scheduleKill() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) { [self] in
            lock.lock()
            if !completed && process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            lock.unlock()
        }
    }
}

// Only written by the stderr reader, then read after its DispatchGroup completes.
private final class DataBox: @unchecked Sendable { var value = Data() }
