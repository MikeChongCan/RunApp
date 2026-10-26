import Foundation

/// Tracks whether the SweetPad CLI is installed and installs it with Homebrew.
@MainActor
@Observable
final class Toolchain {
    enum InstallState: Equatable {
        case idle
        case installing
        case failed(String)
    }

    static let installCommand = "brew install sweetpad-dev/tap/sweetpad"

    private(set) var sweetPad: URL?
    private(set) var brew: URL?
    private(set) var installState: InstallState = .idle
    /// Output of the running or last `brew install`.
    private(set) var log: [String] = []
    /// The user chose "Later" this launch.
    var dismissed = false

    private var installTask: Task<Void, Never>?

    var needsSweetPad: Bool {
        sweetPad == nil && !dismissed
    }

    func check() {
        sweetPad = SweetPadClient.locateBinary()
        brew = Self.locateBrew()
    }

    func install() {
        guard let brew, installState != .installing else { return }
        installState = .installing
        log = ["$ \(Self.installCommand)"]
        installTask = Task {
            do {
                for try await line in Self.brewInstall(brew: brew) {
                    log.append(line)
                }
                installState = .idle
                check()
                if sweetPad == nil {
                    installState = .failed("Homebrew finished, but sweetpad still isn't on disk.")
                }
            } catch {
                installState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    static func locateBrew(fileManager: FileManager = .default) -> URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    struct BrewFailed: LocalizedError {
        let status: Int32
        var errorDescription: String? {
            "brew install exited with status \(status)."
        }
    }

    /// Runs `brew install sweetpad-dev/tap/sweetpad`, yielding stdout+stderr lines. Cancelling sends SIGTERM.
    nonisolated static func brewInstall(brew: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = brew
            process.arguments = ["install", "sweetpad-dev/tap/sweetpad"]
            var env = SweetPadClient.childEnvironment()
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["NONINTERACTIVE"] = "1"
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            let splitter = LineSplitter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                for line in splitter.feed(handle.availableData) {
                    continuation.yield(String(decoding: line, as: UTF8.self))
                }
            }
            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                for line in splitter.feed(rest) + splitter.flush() {
                    continuation.yield(String(decoding: line, as: UTF8.self))
                }
                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: BrewFailed(status: process.terminationStatus))
                }
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
}
