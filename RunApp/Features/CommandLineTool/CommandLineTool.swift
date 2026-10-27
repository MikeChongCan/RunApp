import AppKit

/// Installs the `runapp` shim (`RunApp.app/Contents/Resources/runapp`) as a symlink in `/usr/local/bin`,
/// like Xcode's `xed`. Asks for an administrator password when that folder isn't writable.
@MainActor
enum CommandLineTool {
    nonisolated static let linkPath = "/usr/local/bin/runapp"

    enum Status: Equatable {
        case notInstalled
        /// The link already points at this app's script.
        case installed
        /// Something else is at `linkPath` (another copy of RunApp, or an unrelated file).
        case other(String)
    }

    nonisolated static func status(
        link: String = linkPath,
        script: String,
        fileManager: FileManager = .default
    ) -> Status {
        guard (try? fileManager.attributesOfItem(atPath: link)) != nil else { return .notInstalled }
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link) else {
            return .other(link)
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: link).deletingLastPathComponent())
            .standardizedFileURL.path
        return resolved == URL(fileURLWithPath: script).standardizedFileURL.path ? .installed : .other(resolved)
    }

    /// App menu › Install Command Line Tool…
    static func presentInstall() {
        guard let script = Bundle.main.url(forResource: "runapp", withExtension: nil)?.path else {
            showAlert("The runapp script is missing from this copy of RunApp.", style: .critical)
            return
        }
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            showAlert(
                "Move RunApp to the Applications folder first",
                info: "macOS is running RunApp from a temporary location, so a link to it would stop working.",
                style: .warning
            )
            return
        }

        let current = status(script: script)
        if current == .installed {
            showAlert("The runapp command is already installed", info: usage)
            return
        }

        let confirm = NSAlert()
        confirm.messageText = "Install the runapp command?"
        var info = "RunApp will create a link at \(linkPath). You may be asked for an administrator password."
        if case let .other(existing) = current {
            info += "\n\nThis replaces the existing \(linkPath) (\(existing))."
        }
        confirm.informativeText = info
        confirm.addButton(withTitle: "Install")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let installed = try await install(script: script)
                if installed {
                    showAlert("The runapp command is installed", info: usage)
                }
            } catch {
                showAlert("Couldn't install the runapp command", info: error.localizedDescription, style: .critical)
            }
        }
    }

    private static let usage = "In Terminal, run `runapp .` in a project folder, or `runapp path/to/App.xcodeproj`."

    /// Links without a password when possible, otherwise through `osascript … with administrator privileges`.
    /// Returns `false` when the user cancels the password prompt.
    nonisolated static func install(script: String, link: String = linkPath) async throws -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                atPath: (link as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if (try? fileManager.attributesOfItem(atPath: link)) != nil {
                try fileManager.removeItem(atPath: link)
            }
            try fileManager.createSymbolicLink(atPath: link, withDestinationPath: script)
            return true
        } catch {
            return try await installAsAdmin(script: script, link: link)
        }
    }

    struct InstallFailed: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    private nonisolated static func installAsAdmin(script: String, link: String) async throws -> Bool {
        let source = """
        on run argv
            set dir to do shell script "dirname " & quoted form of item 2 of argv
            set cmd to "mkdir -p " & quoted form of dir & " && ln -sfn " & quoted form of item 1 of argv
            do shell script cmd & " " & quoted form of item 2 of argv with administrator privileges
        end run
        """
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source, script, link]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: true)
                } else if message.contains("-128") {
                    // User canceled the password prompt.
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(throwing: InstallFailed(message: message.isEmpty
                            ? "osascript exited with status \(process.terminationStatus)."
                            : message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func showAlert(_ message: String, info: String = "", style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }
}
