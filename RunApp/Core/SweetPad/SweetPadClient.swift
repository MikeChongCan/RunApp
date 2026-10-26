import Foundation

enum SweetPadClientError: Error, Sendable, LocalizedError {
    /// No `sweetpad` binary found. Show onboarding.
    case binaryNotFound
    /// The process exited non-zero. `error` is the decoded envelope error when SweetPad printed one.
    case failed(exitCode: Int32, error: SweetPadErrorPayload?, stderr: String)
    /// The output wasn't the expected JSON.
    case decoding(underlying: String, output: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "The sweetpad command-line tool was not found. Install it with: brew install sweetpad-dev/tap/sweetpad"
        case let .failed(code, error, stderr):
            error?.message ?? "sweetpad exited with status \(code): \(stderr)"
        case let .decoding(underlying, _):
            "Unexpected sweetpad output: \(underlying)"
        }
    }

    var exitCode: SweetPadExitCode? {
        if case let .failed(code, _, _) = self {
            return SweetPadExitCode(rawValue: code)
        }
        return nil
    }

    /// True when onboarding should be shown (binary missing, or SweetPad reported a missing tool).
    var needsOnboarding: Bool {
        switch self {
        case .binaryNotFound: true
        case let .failed(code, error, _): code == SweetPadExitCode.toolMissing.rawValue || error?.code == "tool_missing"
        case .decoding: false
        }
    }
}

/// Output of one finished `sweetpad` invocation.
struct ProcessOutput: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

/// The only place that spawns `sweetpad`. Never scrape human output: use `json(_:)` or `stream(_:)`.
struct SweetPadClient: Sendable {
    /// Directory SweetPad runs in (passed as `-C`). Usually the folder holding the project.
    var workingDirectory: URL?

    init(workingDirectory: URL? = nil) {
        self.workingDirectory = workingDirectory
    }

    // MARK: Binary lookup

    /// `$RUNAPP_SWEETPAD`, `/opt/homebrew/bin`, `/usr/local/bin`, then `$PATH`.
    /// A GUI app launched from Finder gets a minimal PATH, so the fixed locations come first.
    static func locateBinary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []
        if let override = environment["RUNAPP_SWEETPAD"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append("/opt/homebrew/bin/sweetpad")
        candidates.append("/usr/local/bin/sweetpad")
        for dir in (environment["PATH"] ?? "").split(separator: ":") where !dir.isEmpty {
            candidates.append("\(dir)/sweetpad")
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Environment for child processes: inherits ours, makes sure Homebrew and system tools are on PATH,
    /// and turns off color and prompts.
    static func childEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var path = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in extra.reversed() where !path.contains(dir) {
            path.insert(dir, at: 0)
        }
        env["PATH"] = path.joined(separator: ":")
        env["NO_COLOR"] = "1"
        env["SWEETPAD_NONINTERACTIVE"] = "1"
        return env
    }

    // MARK: Raw execution

    /// Runs `sweetpad <args>` to completion and returns stdout. Throws `.failed` on a non-zero exit.
    /// Arguments are passed verbatim: add `-o json` yourself, or use `json(_:)`.
    func run(args: [String]) async throws -> Data {
        let output = try await execute(args: args)
        guard output.exitCode == 0 else {
            throw SweetPadClientError.failed(
                exitCode: output.exitCode,
                error: Self.decodeError(from: output),
                stderr: String(decoding: output.stderr, as: UTF8.self)
            )
        }
        return output.stdout
    }

    /// Runs `sweetpad <args>` and returns exit code plus both streams, without throwing on non-zero exit.
    func execute(args: [String]) async throws -> ProcessOutput {
        let process = try makeProcess(args: args)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutBuffer = LockedData()
        let stderrBuffer = LockedData()
        stdoutPipe.fileHandleForReading.readabilityHandler = { stdoutBuffer.append($0.availableData) }
        stderrPipe.fileHandleForReading.readabilityHandler = { stderrBuffer.append($0.availableData) }

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
                process.terminationHandler = { finished in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    // Drain whatever is left after the handlers stop.
                    stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    continuation.resume(returning: ProcessOutput(
                        exitCode: finished.terminationStatus,
                        stdout: stdoutBuffer.value,
                        stderr: stderrBuffer.value
                    ))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    // MARK: JSON envelope

    /// Runs `sweetpad <args> -o json --non-interactive` and decodes `data` as `Payload`.
    func json<Payload: Decodable & Sendable>(_ args: [String], as _: Payload.Type = Payload.self) async throws -> Payload {
        let output = try await execute(args: args + ["-o", "json", "--non-interactive"])
        return try Self.decodePayload(Payload.self, from: output)
    }

    static func decodePayload<Payload: Decodable & Sendable>(_: Payload.Type, from output: ProcessOutput) throws -> Payload {
        if output.exitCode != 0 {
            throw SweetPadClientError.failed(
                exitCode: output.exitCode,
                error: decodeError(from: output),
                stderr: String(decoding: output.stderr, as: UTF8.self)
            )
        }
        let envelope = try decodeEnvelope(Payload.self, from: output.stdout)
        if let data = envelope.data, envelope.ok {
            return data
        }
        throw SweetPadClientError.failed(exitCode: output.exitCode, error: envelope.error, stderr: "")
    }

    static func decodeEnvelope<Payload: Decodable & Sendable>(_: Payload.Type, from data: Data) throws -> SweetPadEnvelope<Payload> {
        do {
            return try JSONDecoder().decode(SweetPadEnvelope<Payload>.self, from: data)
        } catch {
            throw SweetPadClientError.decoding(underlying: String(describing: error), output: String(decoding: data, as: UTF8.self))
        }
    }

    /// Errors come as an envelope on **stderr** (`-o json`), or as the last `event: result` line on stdout (`-o ndjson`).
    static func decodeError(from output: ProcessOutput) -> SweetPadErrorPayload? {
        struct ErrorOnly: Decodable {
            let error: SweetPadErrorPayload?
        }
        for stream in [output.stderr, output.stdout] {
            for line in stream.split(separator: UInt8(ascii: "\n")).reversed() {
                if let error = try? JSONDecoder().decode(ErrorOnly.self, from: Data(line)).error {
                    return error
                }
            }
            if let error = try? JSONDecoder().decode(ErrorOnly.self, from: stream).error {
                return error
            }
        }
        return nil
    }

    // MARK: NDJSON streaming

    /// Runs `sweetpad <args> -o ndjson --non-interactive` and yields one `BuildEvent` per line.
    /// Use for `build`, `test`, and `run --no-logs`. Cancelling the consuming task sends SIGTERM.
    /// The stream finishes after the process exits; the last event is normally `.result`.
    /// stderr (which repeats the error envelope on failure) is ignored here.
    func stream(_ args: [String]) -> AsyncThrowingStream<BuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let process: Process
            do {
                process = try makeProcess(args: args + ["-o", "ndjson", "--non-interactive"])
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            let splitter = LineSplitter()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                for line in splitter.feed(handle.availableData) {
                    if let event = BuildEvent.parse(line: line) {
                        continuation.yield(event)
                    }
                }
            }
            process.terminationHandler = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                let rest = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                for line in splitter.feed(rest) + splitter.flush() {
                    if let event = BuildEvent.parse(line: line) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            let box = ProcessBox(process)
            continuation.onTermination = { _ in box.terminate() }
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: Helpers

    private func makeProcess(args: [String]) throws -> Process {
        guard let binary = Self.locateBinary() else {
            throw SweetPadClientError.binaryNotFound
        }
        let process = Process()
        process.executableURL = binary
        var fullArgs: [String] = []
        if let workingDirectory {
            fullArgs += ["-C", workingDirectory.path]
            process.currentDirectoryURL = workingDirectory
        }
        process.arguments = fullArgs + args
        process.environment = Self.childEnvironment()
        return process
    }
}

// MARK: - Small thread-safe helpers

/// Accumulates pipe output from `readabilityHandler` callbacks (which run on arbitrary threads).
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock { data.append(chunk) }
    }

    var value: Data {
        lock.withLock { data }
    }
}

/// Splits a byte stream into `\n`-terminated lines.
final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func feed(_ chunk: Data) -> [Data] {
        lock.withLock {
            buffer.append(chunk)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex ..< newline]
                if !line.isEmpty {
                    lines.append(Data(line))
                }
                buffer.removeSubrange(buffer.startIndex ... newline)
            }
            return lines
        }
    }

    func flush() -> [Data] {
        lock.withLock {
            defer { buffer.removeAll() }
            return buffer.isEmpty ? [] : [buffer]
        }
    }
}

/// Lets a cancellation handler terminate a `Process` from another isolation domain.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        if process.isRunning {
            process.terminate() // SIGTERM
        }
    }
}
