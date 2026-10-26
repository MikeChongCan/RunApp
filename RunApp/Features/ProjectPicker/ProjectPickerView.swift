import SwiftUI

/// Lists every project found under the opened folder, with a filter field. Return or double-click opens one.
struct ProjectPickerView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection: ProjectCandidate.ID?
    @FocusState private var searchFocused: Bool

    private var filtered: [ProjectCandidate] {
        model.candidates.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose a project")
                    .font(.title2.bold())
                if let root = model.openedPath {
                    Text("\(model.candidates.count) found in \(root.abbreviatingWithTilde)")
                        .foregroundStyle(.secondary)
                }
                TextField("Filter by name or path", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit(openSelection)
                    .onKeyPress(.downArrow) { moveSelection(by: 1) }
                    .onKeyPress(.upArrow) { moveSelection(by: -1) }
            }
            .padding(20)

            List(filtered, selection: $selection) { candidate in
                ProjectCandidateRow(candidate: candidate)
                    .tag(candidate.id)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
                        }
                    }
            }
            .contextMenu(forSelectionType: ProjectCandidate.ID.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first {
                    open(id)
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            Divider()
            HStack {
                Button("Open Other…") { model.presentOpenPanel() }
                Spacer()
                if let candidate = selectedCandidate, let command = candidate.generateCommand {
                    Text("Run `\(command)` first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Button("Open", action: openSelection)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedCandidate?.located == nil)
            }
            .padding(12)
        }
        .onAppear {
            searchFocused = true
            selection = filtered.first?.id
        }
        .onChange(of: query) {
            if !filtered.contains(where: { $0.id == selection }) {
                selection = filtered.first?.id
            }
        }
    }

    private var selectedCandidate: ProjectCandidate? {
        model.candidates.first { $0.id == selection }
    }

    private func openSelection() {
        if let selection {
            open(selection)
        }
    }

    private func open(_ id: ProjectCandidate.ID) {
        if let candidate = model.candidates.first(where: { $0.id == id }), candidate.located != nil {
            model.select(candidate)
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let items = filtered
        guard !items.isEmpty else { return .ignored }
        let current = items.firstIndex { $0.id == selection } ?? -offset
        let next = min(max(current + offset, 0), items.count - 1)
        selection = items[next].id
        return .handled
    }
}

private struct ProjectCandidateRow: View {
    let candidate: ProjectCandidate

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(candidate.located == nil ? .secondary : Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .fontWeight(.medium)
                Text(candidate.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let generator = candidate.generator, candidate.located != nil {
                Badge(text: generator.rawValue)
            }
            Badge(text: candidate.located == nil ? "\(candidate.kindLabel) · not generated" : candidate.kindLabel)
        }
        .padding(.vertical, 3)
    }

    private var symbol: String {
        switch candidate.kind {
        case .workspace: "square.stack.3d.up"
        case .project: "hammer"
        case .package: "shippingbox"
        case .spec: "doc.badge.gearshape"
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}

extension URL {
    /// `/Users/me/Developer/x` → `~/Developer/x`.
    var abbreviatingWithTilde: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
