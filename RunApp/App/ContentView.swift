import SwiftUI

/// Placeholder root view. The real layout (toolbar, sidebar, console) lives in `Features/`.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let project = model.project {
                ContentUnavailableView {
                    Label(project.displayName, systemImage: "hammer")
                } description: {
                    Text(project.url.path)
                }
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
}
