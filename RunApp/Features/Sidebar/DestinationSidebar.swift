import SwiftUI

/// Destinations grouped like Xcode's run-destination menu: this Mac, connected devices, simulators.
struct DestinationSidebar: View {
    @Bindable var session: RunSession
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: $session.destinationID) {
            Section("Project") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.project.displayName)
                        .fontWeight(.semibold)
                    Text(session.project.url.abbreviatingWithTilde)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .selectionDisabled()
                if model.candidates.count > 1 {
                    Button("Switch Project…") { model.showPicker() }
                        .buttonStyle(.link)
                        .selectionDisabled()
                }
            }

            group("This Mac", kinds: [.mac])
            group("Devices", kinds: [.usb, .wifi])
            group("Simulators", kinds: [.simulator])
        }
        .listStyle(.sidebar)
        .overlay {
            if session.destinations.isEmpty, !session.isLoading {
                ContentUnavailableView("No destinations", systemImage: "iphone.slash")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(session.destinations.count) destinations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await session.refreshDestinations() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Refresh devices (⇧⌘R)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func group(_ title: String, kinds: Set<Destination.Kind>) -> some View {
        let items = session.destinations.filter { kinds.contains($0.kind) }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { destination in
                    DestinationRow(destination: destination)
                        .tag(destination.id)
                }
            }
        }
    }
}

struct DestinationRow: View {
    let destination: Destination

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(destination.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .opacity(destination.connection == "unavailable" ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch destination.kind {
        case .mac: "laptopcomputer"
        case .simulator: destination.os == "iOS" && destination.name.contains("iPad") ? "ipad" : "iphone"
        case .usb, .wifi:
            switch destination.os {
            case "watchOS": "applewatch"
            case "tvOS": "appletv"
            case "visionOS": "visionpro"
            default: destination.name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone"
            }
        }
    }

    private var subtitle: String {
        var parts = [destination.osVersion.isEmpty ? destination.os : "\(destination.os) \(destination.osVersion)"]
        if destination.booted == true {
            parts.append("Booted")
        }
        if let connection = destination.connection, connection != "connected" {
            parts.append(connection.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private var badge: String? {
        switch destination.kind {
        case .usb: "USB"
        case .wifi: "Wi‑Fi"
        case .mac, .simulator: nil
        }
    }
}
