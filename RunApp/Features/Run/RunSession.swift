import Foundation

/// One line in the console.
struct ConsoleLine: Identifiable, Sendable, Hashable {
    enum Kind: Sendable {
        case command
        case task
        case warning
        case error
        case success
        case output
        case info
    }

    enum Channel: Sendable {
        case build
        case app
    }

    let id: Int
    let kind: Kind
    let channel: Channel
    let text: String
}

/// A line of `sweetpad app logs -o ndjson`: either `{eventMessage, source, timestamp}` (macOS stdout/stderr)
/// or a raw `log stream --style json` object. Both carry `eventMessage`.
private struct AppLogLine: Decodable {
    let eventMessage: String?
    let messageType: String?
}

/// Everything behind the main window for one opened project: schemes, configurations, destinations,
/// and the build → run → logs → stop cycle.
@MainActor
@Observable
final class RunSession {
    enum Phase: Equatable {
        case idle
        case building
        case running(bundleID: String?)
        case stopping
    }

    let project: LocatedProject
    private let client: SweetPadClient

    private(set) var schemes: [String] = []
    private(set) var configurations: [String] = ["Debug", "Release"]
    private(set) var destinations: [Destination] = []
    var scheme: String?
    var configuration = "Debug"
    var destinationID: Destination.ID?

    private(set) var phase: Phase = .idle
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var lines: [ConsoleLine] = []
    /// Short live status: "Compiling Foo.swift", "Build failed", …
    private(set) var status = "Ready"
    private(set) var warningCount = 0
    private(set) var errorCount = 0

    private var nextLineID = 0
    private var runTask: Task<Void, Never>?
    private var logsTask: Task<Void, Never>?
    private static let maxLines = 20000

    init(project: LocatedProject) {
        self.project = project
        client = SweetPadClient(workingDirectory: project.directory)
    }

    var destination: Destination? {
        destinations.first { $0.id == destinationID }
    }

    var isBusy: Bool {
        phase != .idle
    }

    var canRun: Bool {
        runBlocker == nil && phase == .idle
    }

    /// Why Play is disabled, if it is. A `"disconnected"` device is still allowed: devicectl opens the
    /// tunnel on demand (USB or same Wi-Fi). `"unavailable"` means it can't be reached at all.
    var runBlocker: String? {
        if isLoading {
            return "Loading project…"
        }
        if scheme == nil {
            return "No scheme"
        }
        guard let destination else { return "Choose a destination" }
        if destination.connection == "unavailable" {
            return "\(destination.name) is unavailable"
        }
        return nil
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let args = project.sweetPadArguments
        async let schemeList = client.json(["scheme", "list"] + args, as: SchemeListPayload.self)
        async let info = client.json(["project", "info"] + args, as: ProjectInfoPayload.self)
        async let status = client.json(["status"] + args, as: StatusPayload.self)
        async let devices = client.json(["devices"], as: DevicesPayload.self)

        do {
            let list = try await schemeList
            schemes = list.schemes.map(\.name)
            scheme = list.selected ?? schemes.first { $0 == project.displayName } ?? schemes.first
        } catch {
            loadError = error.localizedDescription
        }
        if let configs = try? await info.configurations, !configs.isEmpty {
            configurations = configs
            if !configs.contains(configuration) {
                configuration = configs[0]
            }
        }
        let remembered = try? await status
        if let value = remembered?.context.configuration.value, configurations.contains(value) {
            configuration = value
        }
        if let found = try? await devices.destinations {
            destinations = found
        }
        let rememberedDestination = remembered?.context.destination.value
        destinationID = destinations.first { $0.destination == rememberedDestination }?.id
            ?? destinations.first { $0.isAvailable && $0.kind != .mac }?.id
            ?? destinations.first?.id
    }

    func refreshDestinations() async {
        guard let found = try? await client.json(["devices"], as: DevicesPayload.self) else { return }
        destinations = found.destinations
        if destination == nil {
            destinationID = destinations.first?.id
        }
    }

    // MARK: Run / stop

    func run() {
        guard canRun, let scheme, let destination else { return }
        lines.removeAll()
        warningCount = 0
        errorCount = 0
        phase = .building
        status = "Building \(scheme)…"

        let args = ["run", "--scheme", scheme, "--on", destination.onArgument, "--configuration", configuration, "--detach"]
            + project.sweetPadArguments
        append(.command, "$ sweetpad \(args.joined(separator: " "))")

        runTask = Task {
            var result: ResultLine?
            do {
                for try await event in client.stream(args) {
                    handle(event)
                    if case let .result(line) = event {
                        result = line
                    }
                }
            } catch {
                append(.error, error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            finishBuild(result, destination: destination)
        }
    }

    private func handle(_ event: BuildEvent) {
        switch event {
        case let .task(kind, name):
            status = "\(kind.capitalized) \(name)"
            append(.task, "▸ \(kind.capitalized) \(name)")
        case let .diagnostic(diagnostic):
            let location = diagnostic.location.map { ($0 as NSString).lastPathComponent + "  " } ?? ""
            if diagnostic.severity == "error" {
                errorCount += 1
                append(.error, "✖ \(location)\(diagnostic.message)")
            } else {
                warningCount += 1
                append(.warning, "⚠ \(location)\(diagnostic.message)")
            }
        case .result:
            break
        case let .other(_, raw):
            append(.info, String(decoding: raw, as: UTF8.self))
        }
    }

    private func finishBuild(_ result: ResultLine?, destination: Destination) {
        guard let result, result.ok else {
            let message = result?.error?.message ?? "sweetpad exited without a result"
            append(.error, "✖ \(message)")
            status = "Build failed"
            phase = .idle
            return
        }
        let seconds = (result.data?.durationMs).map { String(format: " in %.1f s", Double($0) / 1000) } ?? ""
        append(.success, "✓ Build succeeded\(seconds)")
        let bundleID = result.data?.bundleId
        append(.success, "✓ Launched \(bundleID ?? "app") on \(destination.name)")
        status = "Running on \(destination.name)"
        phase = .running(bundleID: bundleID)
        followLogs()
        if destination.kind == .mac, let pid = result.data?.pid {
            watchExit(pid: pid_t(pid))
        }
    }

    /// `app logs` keeps following after the app quits, so poll the macOS process and end the run when it's gone.
    private func watchExit(pid: pid_t) {
        Task {
            while case .running = phase {
                try? await Task.sleep(for: .seconds(1))
                if kill(pid, 0) != 0, errno == ESRCH, case .running = phase {
                    logsTask?.cancel()
                    logsTask = nil
                    append(.info, "App exited", channel: .app)
                    status = "Stopped"
                    phase = .idle
                }
            }
        }
    }

    private func followLogs() {
        logsTask = Task {
            do {
                for try await raw in client.streamLines(["app", "logs", "--non-interactive", "-o", "ndjson"]) {
                    guard let line = try? JSONDecoder().decode(AppLogLine.self, from: raw),
                          let message = line.eventMessage
                    else { continue }
                    let kind: ConsoleLine.Kind = ["Error", "Fault"].contains(line.messageType ?? "") ? .error : .output
                    append(kind, message, channel: .app)
                }
            } catch {
                append(.info, "Logs ended: \(error.localizedDescription)", channel: .app)
            }
            guard !Task.isCancelled else { return }
            if case .running = phase {
                append(.info, "App exited", channel: .app)
                status = "Stopped"
                phase = .idle
            }
        }
    }

    func stop() {
        switch phase {
        case .idle, .stopping:
            return
        case .building:
            runTask?.cancel()
            runTask = nil
            append(.info, "Build cancelled")
            status = "Cancelled"
            phase = .idle
        case .running:
            phase = .stopping
            status = "Stopping…"
            logsTask?.cancel()
            logsTask = nil
            Task {
                do {
                    _ = try await client.json(["app", "stop"] + stopArguments, as: AppStopPayload.self)
                    append(.info, "Stopped", channel: .app)
                } catch {
                    append(.error, "Stop failed: \(error.localizedDescription)", channel: .app)
                }
                status = "Stopped"
                phase = .idle
            }
        }
    }

    private var stopArguments: [String] {
        guard let scheme, let destination else { return [] }
        return ["--scheme", scheme, "--on", destination.onArgument] + project.sweetPadArguments
    }

    func clean() {
        guard phase == .idle, let scheme else { return }
        let args = ["clean", "--scheme", scheme, "--configuration", configuration] + project.sweetPadArguments
        append(.command, "$ sweetpad \(args.joined(separator: " "))")
        status = "Cleaning…"
        Task {
            do {
                _ = try await client.json(args, as: EmptyPayload.self)
                append(.success, "✓ Clean finished")
                status = "Cleaned"
            } catch {
                append(.error, "✖ \(error.localizedDescription)")
                status = "Clean failed"
            }
        }
    }

    func clearConsole() {
        lines.removeAll()
    }

    /// Ends child processes when the window goes away. Leaves a launched app running, as Xcode does.
    func tearDown() {
        runTask?.cancel()
        logsTask?.cancel()
    }

    private func append(_ kind: ConsoleLine.Kind, _ text: String, channel: ConsoleLine.Channel = .build) {
        lines.append(ConsoleLine(id: nextLineID, kind: kind, channel: channel, text: text))
        nextLineID += 1
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }
}
