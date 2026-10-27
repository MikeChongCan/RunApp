import SwiftUI

@main
struct RunAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.model)
                .environment(appDelegate.toolchain)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { appDelegate.model.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: appDelegate.updater)
                Button("Install Command Line Tool…") { CommandLineTool.presentInstall() }
            }
        }
    }
}

/// App-wide state. UI state lives on the main actor.
@MainActor
@Observable
final class AppModel {
    /// The path RunApp was opened with (folder or project file), as given.
    private(set) var openedPath: URL?
    /// The project being worked on, or `nil` while none is chosen.
    private(set) var project: LocatedProject?
    /// Everything found under `openedPath` when it is a folder. More than one → the picker is shown.
    private(set) var candidates: [ProjectCandidate] = []
    private(set) var isDiscovering = false

    private var discoveryTask: Task<Void, Never>?

    /// A project file opens directly. A folder is searched recursively (git-ignored paths skipped):
    /// a single result opens, several show the picker.
    func open(_ url: URL) {
        let url = url.standardizedFileURL
        openedPath = url
        project = nil
        candidates = []
        discoveryTask?.cancel()

        var isDirectory: ObjCBool = false
        let isPlainFolder = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !["xcodeproj", "xcworkspace"].contains(url.pathExtension)
        guard isPlainFolder else {
            project = ProjectLocator.locate(url)
            return
        }

        isDiscovering = true
        discoveryTask = Task {
            let found = await Task.detached(priority: .userInitiated) {
                await ProjectDiscovery.discover(in: url)
            }.value
            guard !Task.isCancelled else { return }
            candidates = found
            isDiscovering = false
            if found.count == 1, let only = found.first?.located {
                project = only
            }
        }
    }

    func select(_ candidate: ProjectCandidate) {
        project = candidate.located
    }

    /// Back to the picker for the same folder.
    func showPicker() {
        project = nil
    }

    /// Lets the user pick a folder, `.xcodeproj`, `.xcworkspace` or `Package.swift`.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder, Xcode project, workspace or Swift package"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }
}

/// Receives the project path from `runapp <path>`:
/// - fresh launch: `open -a RunApp --args <abs path>` → `CommandLine.arguments`
/// - already running: `open -a RunApp <abs path>` → `application(_:open:)`
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let toolchain = Toolchain()
    let updater = Updater()

    func applicationWillFinishLaunching(_: Notification) {
        if let url = ProjectLocator.pathArgument(from: CommandLine.arguments) {
            model.open(url)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        updater.start()
    }

    func application(_: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            model.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
