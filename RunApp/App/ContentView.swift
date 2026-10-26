import SwiftUI

/// Placeholder root view. The real layout (toolbar, sidebar, console) lives in `Features/`.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(Toolchain.self) private var toolchain

    var body: some View {
        Group {
            if let project = model.project {
                ContentUnavailableView {
                    Label(project.displayName, systemImage: "hammer")
                } description: {
                    Text(project.url.path)
                } actions: {
                    if model.candidates.count > 1 {
                        Button("Switch Project…") { model.showPicker() }
                    }
                }
            } else if model.isDiscovering {
                ProgressView("Looking for projects…")
            } else if !model.candidates.isEmpty {
                ProjectPickerView()
            } else if let path = model.openedPath {
                ContentUnavailableView {
                    Label("No Xcode project found", systemImage: "questionmark.folder")
                } description: {
                    Text("Nothing buildable in \(path.path)")
                } actions: {
                    openButton
                }
            } else {
                ContentUnavailableView {
                    Label("Open a project", systemImage: "play.rectangle")
                } description: {
                    Text("Run `runapp .` in a folder with an Xcode project.")
                } actions: {
                    openButton
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task { toolchain.check() }
        .sheet(isPresented: Binding(
            get: { toolchain.needsSweetPad },
            set: {
                if !$0 {
                    toolchain.dismissed = true
                }
            }
        )) {
            SweetPadInstallView()
        }
    }

    private var openButton: some View {
        Button("Open…") { model.presentOpenPanel() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .environment(Toolchain())
}
