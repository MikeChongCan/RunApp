import SwiftUI

/// Main window for an opened project: destinations sidebar, console, and a toolbar with
/// Play/Stop plus scheme and configuration pickers.
struct RunView: View {
    @State private var session: RunSession

    init(project: LocatedProject) {
        _session = State(initialValue: RunSession(project: project))
    }

    var body: some View {
        NavigationSplitView {
            DestinationSidebar(session: session)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            ConsoleView(session: session)
        }
        .navigationTitle(session.project.displayName)
        .navigationSubtitle(session.status)
        .toolbar { toolbar }
        .task { await session.load() }
        .task {
            // Wi-Fi devices come and go; keep the list fresh while the window is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if !session.isBusy {
                    await session.refreshDestinations()
                }
            }
        }
        .onDisappear { session.tearDown() }
        .overlay(alignment: .top) {
            if let error = session.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if session.isBusy {
                Button("Stop", systemImage: "stop.fill") { session.stop() }
                    .keyboardShortcut(".")
                    .disabled(session.phase == .stopping)
                    .help("Stop (⌘.)")
            } else {
                Button("Run", systemImage: "play.fill") { session.run() }
                    .keyboardShortcut("r")
                    .disabled(!session.canRun)
                    .help(session.runBlocker ?? "Build and run (⌘R)")
            }
        }

        ToolbarItemGroup(placement: .principal) {
            Picker("Scheme", selection: $session.scheme) {
                ForEach(session.schemes, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .help("Scheme")
            .disabled(session.isBusy || session.schemes.isEmpty)

            Picker("Destination", selection: $session.destinationID) {
                ForEach(session.destinations) { destination in
                    Text(destination.displayName).tag(Optional(destination.id))
                }
            }
            .help("Run destination")
            .disabled(session.isBusy)

            Picker("Configuration", selection: $session.configuration) {
                ForEach(session.configurations, id: \.self) { Text($0).tag($0) }
            }
            .help("Build configuration")
            .disabled(session.isBusy)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if session.phase == .building {
                ProgressView().controlSize(.small)
            }
            Button("Clean", systemImage: "paintbrush") { session.clean() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(session.isBusy || session.scheme == nil)
                .help("Clean build folder (⇧⌘K)")
            Button("Open in Xcode", systemImage: "hammer") {
                NSWorkspace.shared.open(session.project.url)
            }
            .help("Open in Xcode")
        }
    }
}
