import Foundation

/// A runnable target, decoded from one entry of `sweetpad devices -o json` → `data.destinations[]`.
///
/// Real shape (sweetpad 0.1.14), see docs/sweetpad-cli.md:
/// ```json
/// {"kind": "macOS", "name": "My Mac", "os": "macOS", "osVersion": "", "udid": null,
///  "destination": "platform=macOS", "booted": null, "connection": null, "transport": null, "pairing": null}
/// {"kind": "simulator", "name": "iPhone 17", "os": "iOS", "osVersion": "27.0", "udid": "75BC…",
///  "destination": "platform=iOS Simulator,id=75BC…", "booted": false, "connection": null, "transport": null, "pairing": null}
/// {"kind": "device", "name": "Alex-iPhone", "os": "iOS", "osVersion": "27.0.1", "udid": "00008140-…",
///  "destination": "platform=iOS,id=00008140-…", "booted": null,
///  "connection": "disconnected", "transport": "localNetwork", "pairing": "paired"}
/// ```
/// SweetPad has no explicit USB/Wi-Fi field: `transport` (devicectl's `transportType`) is
/// `"wired"` for USB and `"localNetwork"` for Wi-Fi. It can also be `""` for a device that was never seen.
struct Destination: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case mac
        case usb
        case wifi
        case simulator
    }

    /// SweetPad's own `kind` value: `"macOS"`, `"simulator"` or `"device"`.
    let sweetPadKind: String
    let name: String
    /// Platform, e.g. `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS`.
    let os: String
    let osVersion: String
    /// `nil` for "My Mac".
    let udid: String?
    /// Ready-made xcodebuild `-destination` specifier.
    let destination: String
    /// Simulators only.
    let booted: Bool?
    /// Devices only: `"connected"`, `"disconnected"`, `"unavailable"` (devicectl tunnel state).
    let connection: String?
    /// Devices only: `"wired"` (USB), `"localNetwork"` (Wi-Fi), or `""`.
    let transport: String?
    /// Devices only: `"paired"` or not.
    let pairing: String?

    enum CodingKeys: String, CodingKey {
        case sweetPadKind = "kind"
        case name, os, osVersion, udid, destination, booted, connection, transport, pairing
    }

    var id: String {
        udid ?? destination
    }

    var kind: Kind {
        switch sweetPadKind {
        case "macOS": .mac
        case "simulator": .simulator
        default: transport == "localNetwork" ? .wifi : .usb
        }
    }

    /// Value for `sweetpad … --on <value>`.
    var onArgument: String {
        kind == .mac ? "mac" : (udid ?? name)
    }

    /// Whether Play can target this destination right now without extra steps.
    /// Simulators boot on demand, so they count as available.
    var isAvailable: Bool {
        switch kind {
        case .mac, .simulator: true
        case .usb, .wifi: connection == "connected"
        }
    }

    var displayName: String {
        osVersion.isEmpty ? name : "\(name) (\(os) \(osVersion))"
    }
}

/// `data` of `sweetpad devices -o json`.
struct DevicesPayload: Codable, Sendable {
    let destinations: [Destination]
}

/// Entry of `sweetpad simulator list -o json` → `data.simulators[]`.
struct SimulatorInfo: Codable, Hashable, Sendable {
    let name: String
    let os: String
    let osVersion: String
    let udid: String
    let booted: Bool
    /// simctl state, e.g. `"Booted"`, `"Shutdown"`.
    let state: String
}

struct SimulatorListPayload: Codable, Sendable {
    let simulators: [SimulatorInfo]
}

/// Entry of `sweetpad device list -o json` → `data.devices[]` (paired physical devices).
struct PairedDevice: Codable, Hashable, Sendable {
    let name: String
    let model: String
    let platform: String
    let osVersion: String
    let udid: String
    let connection: String
    let transport: String
    let pairing: String
}

struct DeviceListPayload: Codable, Sendable {
    let devices: [PairedDevice]
}
