import AppKit
import SwiftUI

/// Sheet shown when the SweetPad CLI is missing.
struct SweetPadInstallView: View {
    @Environment(Toolchain.self) private var toolchain

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Install the SweetPad CLI")
                        .font(.title2.bold())
                    Text("RunApp uses SweetPad to list devices, build and run. It isn't installed on this Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(Toolchain.installCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Toolchain.installCommand, forType: .string)
                }
                .labelStyle(.iconOnly)
                .help("Copy command")
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if toolchain.brew == nil {
                Label {
                    Text("Homebrew isn't installed. Get it from [brew.sh](https://brew.sh), then check again.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if !toolchain.log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(toolchain.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(height: 160)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: toolchain.log.count) { proxy.scrollTo("end") }
                }
            }

            if case let .failed(message) = toolchain.installState {
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Later") { toolchain.dismissed = true }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Check Again") { toolchain.check() }
                    .disabled(toolchain.installState == .installing)
                if toolchain.installState == .installing {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { toolchain.cancelInstall() }
                } else {
                    Button("Install with Homebrew") { toolchain.install() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(toolchain.brew == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(toolchain.installState == .installing)
    }
}

#Preview {
    SweetPadInstallView()
        .environment(Toolchain())
}
