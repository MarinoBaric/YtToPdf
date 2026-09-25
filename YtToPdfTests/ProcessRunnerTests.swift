import Foundation
import Synchronization
import Testing
@testable import YtToPdf

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    private let shell = URL(filePath: "/bin/sh")

    @Test func capturesOutputAndExitCode() async throws {
        let result = try await ProcessRunner.run(shell, arguments: ["-c", "printf hello; printf oops >&2; exit 3"])
        #expect(result.exitCode == 3)
        #expect(String(decoding: result.standardOutput, as: UTF8.self) == "hello")
        #expect(result.standardError == "oops")
    }

    @Test func streamsLinesSplitOnCarriageReturns() async throws {
        let lines = Mutex<[String]>([])
        _ = try await ProcessRunner.run(shell, arguments: ["-c", #"printf '10%%\r20%%\rdone\n'"#]) { line in
            lines.withLock { $0.append(line) }
        }
        #expect(lines.withLock { $0 } == ["10%", "20%", "done"])
    }

    @Test func handlesLargeOutput() async throws {
        let result = try await ProcessRunner.run(shell, arguments: ["-c", "head -c 3000000 /dev/zero"])
        #expect(result.standardOutput.count == 3_000_000)
    }

    @Test func usesHomebrewPath() async throws {
        let result = try await ProcessRunner.run(shell, arguments: ["-c", "printf \"$PATH\""])
        #expect(String(decoding: result.standardOutput, as: UTF8.self).hasPrefix("/opt/homebrew/bin:/usr/local/bin"))
    }

    @Test func reportsLaunchFailure() async {
        await #expect(throws: ProcessError.self) {
            try await ProcessRunner.run(URL(filePath: "/nonexistent/tool"), arguments: [])
        }
    }

    @Test func cancellationTerminatesTheProcess() async {
        let started = ContinuousClock.now
        let task = Task {
            try await ProcessRunner.run(URL(filePath: "/bin/sleep"), arguments: ["30"])
        }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()

        let result = await task.result
        #expect(throws: ProcessError.cancelled) { try result.get() }
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
