import SwiftUI

/// Build output and app logs, with a channel switch and a text filter. Follows the tail while new lines arrive.
struct ConsoleView: View {
    let session: RunSession
    @State private var channel: ConsoleLine.Channel = .build
    @State private var filter = ""

    private var visible: [ConsoleLine] {
        session.lines.filter { line in
            line.channel == channel && (filter.isEmpty || line.text.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Output", selection: $channel) {
                    Text("Build").tag(ConsoleLine.Channel.build)
                    Text("App Output").tag(ConsoleLine.Channel.app)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if session.warningCount > 0 {
                    Label("\(session.warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                if session.errorCount > 0 {
                    Label("\(session.errorCount)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                Spacer()
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Button("Clear", systemImage: "trash") { session.clearConsole() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("k")
                    .help("Clear console (⌘K)")
            }
            .padding(8)
            Divider()

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(visible) { line in
                            Text(line.text)
                                .foregroundStyle(color(for: line.kind))
                                .id(line.id)
                        }
                    }
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay {
                    if visible.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: session.lines.last?.id) {
                    if let last = visible.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .background(.background)
        .onChange(of: session.phase) { _, phase in
            if case .running = phase {
                channel = .app
            }
            if phase == .building {
                channel = .build
            }
        }
    }

    private var placeholder: String {
        if !filter.isEmpty {
            return "No lines match “\(filter)”"
        }
        if channel == .app {
            return "App output appears here while it runs."
        }
        return session.runBlocker ?? "Press ⌘R or the Play button to build and run."
    }

    private func color(for kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .command, .task, .info: .secondary
        case .warning: .orange
        case .error: .red
        case .success: .green
        case .output: .primary
        }
    }
}
