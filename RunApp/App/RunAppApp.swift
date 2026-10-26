import SwiftUI

@main
struct RunAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.model)
        }
        .defaultSize(width: 980, height: 640)
    }
}

/// App-wide state. UI state lives on the main actor.
@MainActor
@Observable
final class AppModel {
    /// The path RunApp was opened with (folder or project file), as given.
    private(set) var openedPath: URL?
    /// What `ProjectLocator` found for `openedPath`, or `nil` if nothing buildable is there.
    private(set) var project: LocatedProject?

    func open(_ url: URL) {
        openedPath = url
        project = ProjectLocator.locate(url)
    }
}

/// Receives the project path from `runapp <path>`:
/// - fresh launch: `open -a RunApp --args <abs path>` → `CommandLine.arguments`
/// - already running: `open -a RunApp <abs path>` → `application(_:open:)`
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_: Notification) {
        if let url = ProjectLocator.pathArgument(from: CommandLine.arguments) {
            model.open(url)
        }
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
