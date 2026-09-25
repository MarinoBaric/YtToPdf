import Foundation
import Synchronization

nonisolated struct ProcessResult: Sendable {
    var exitCode: Int32
    var standardOutput: Data
    var standardError: String

    var succeeded: Bool { exitCode == 0 }
}

nonisolated enum ProcessError: Error, Equatable, Sendable {
    case launchFailed(String)
    case cancelled
}

/// Runs an external tool off the main actor and terminates it if the calling task is cancelled.
nonisolated enum ProcessRunner {
    /// Homebrew directories first, so tools find each other (yt-dlp → ffmpeg, deno).
    static let searchPath = (ToolLocator.defaultSearchDirectories.map { $0.standardizedFileURL.path(percentEncoded: false) }
        .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")

    /// - Parameter onOutputLine: Called for every line on stdout or stderr, split on `\n` or `\r`
    ///   so carriage-return progress updates arrive individually.
    @concurrent
    static func run(
        _ executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws(ProcessError) -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let handle = RunningProcess(process)
        let outHandle = stdout.fileHandleForReading
        let errHandle = stderr.fileHandleForReading
        let (launch, outData, errData) = await withTaskCancellationHandler {
            async let out = drain(outHandle, onLine: onOutputLine)
            async let err = drain(errHandle, onLine: onOutputLine)
            let launch = await handle.launchAndWait()
            if case .failure = launch {
                // Nothing will ever write to these, so close them to let the readers hit EOF.
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
            }
            return (launch, await out, await err)
        } onCancel: {
            handle.terminate()
        }

        let exitCode = try launch.get()
        if Task.isCancelled { throw .cancelled }
        return ProcessResult(
            exitCode: exitCode,
            standardOutput: outData,
            standardError: String(decoding: errData, as: UTF8.self)
        )
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        env["PYTHONUNBUFFERED"] = "1"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        return env
    }

    /// Reads a pipe to EOF on a dispatch thread so no Swift concurrency thread blocks.
    private static func drain(_ handle: FileHandle, onLine: (@Sendable (String) -> Void)?) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var data = Data()
                var splitter = LineSplitter()
                while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    data.append(chunk)
                    if let onLine {
                        splitter.append(chunk).forEach(onLine)
                    }
                }
                if let onLine, let last = splitter.flush() { onLine(last) }
                continuation.resume(returning: data)
            }
        }
    }
}

/// Owns a `Process` across launch, wait and cancellation without racing on its state.
/// `@unchecked` because `Process` isn't `Sendable`; every access to it goes through `phase`'s lock
/// or happens before launch.
nonisolated private final class RunningProcess: @unchecked Sendable {
    private enum Phase { case idle, running, finished, cancelled }

    private let process: Process
    private let phase = Mutex(Phase.idle)

    init(_ process: Process) {
        self.process = process
    }

    func launchAndWait() async -> Result<Int32, ProcessError> {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { [self] finished in
                phase.withLock { $0 = .finished }
                continuation.resume(returning: .success(finished.terminationStatus))
            }
            let launchError: ProcessError? = phase.withLock { state in
                guard state == .idle else { return .cancelled }
                do {
                    try process.run()
                    state = .running
                    return nil
                } catch {
                    return .launchFailed(error.localizedDescription)
                }
            }
            if let launchError {
                process.terminationHandler = nil
                continuation.resume(returning: .failure(launchError))
            }
        }
    }

    func terminate() {
        phase.withLock { state in
            switch state {
            case .running: process.terminate()
            case .idle: state = .cancelled
            case .finished, .cancelled: break
            }
        }
    }
}

/// Splits a byte stream into lines on `\n` or `\r`.
nonisolated struct LineSplitter {
    private var pending = Data()

    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = pending[pending.startIndex..<index]
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
            pending.removeSubrange(pending.startIndex...index)
        }
        return lines
    }

    mutating func flush() -> String? {
        defer { pending.removeAll() }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
}
