import Foundation

/// Entry of `sweetpad scheme list -o json` → `data.schemes[]`.
struct Scheme: Codable, Hashable, Sendable, Identifiable {
    let name: String
    /// True when this is SweetPad's remembered scheme for the project.
    let selected: Bool

    var id: String {
        name
    }
}

/// `data` of `sweetpad scheme list -o json`.
struct SchemeListPayload: Codable, Sendable {
    /// Absolute path of the resolved `.xcworkspace` / `.xcodeproj`.
    let container: String
    let schemes: [Scheme]
    /// Remembered scheme name, or `nil`.
    let selected: String?
}

/// `data` of `sweetpad project info -o json`. Source of the configuration list (Debug, Release, …).
struct ProjectInfoPayload: Codable, Sendable {
    let configurations: [String]
    /// `"project"` or `"workspace"`.
    let kind: String
    let name: String
    let path: String
    let schemes: [String]
    let targets: [String]
}

/// A value plus where it came from. Observed sources: `"flag"`, `"env"`, `"config"`, `"remembered"`,
/// `"build remembered"`, `"scheme"`, `"default"`, or `nil` (unset).
struct SourcedValue: Codable, Hashable, Sendable {
    let source: String?
    let value: String?
}

/// `data` of `sweetpad status -o json`: what would build right now, and where each value comes from.
struct StatusPayload: Codable, Sendable {
    struct Context: Codable, Sendable {
        let configuration: SourcedValue
        let destination: SourcedValue
        let scheme: SourcedValue
    }

    /// Absolute path of the resolved `.xcworkspace` / `.xcodeproj`.
    let container: String
    let context: Context
    /// `"project"` or `"workspace"`.
    let kind: String
    let lastLaunchedApp: LastLaunchedApp?
}

/// `lastLaunchedApp` in `sweetpad status` / `sweetpad context show` (note: snake_case keys).
struct LastLaunchedApp: Codable, Sendable, Hashable {
    let appName: String?
    let appPath: String?
    let bundleIdentifier: String?
    let configuration: String?
    let destination: String?
    let executableName: String?
    /// Observed: `"macos"`. Presumably also simulator/device values (unverified).
    let kind: String?
    let scheme: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case appPath = "app_path"
        case bundleIdentifier = "bundle_identifier"
        case configuration, destination
        case executableName = "executable_name"
        case kind, scheme
    }
}

/// `data` of `sweetpad context show -o json` (trimmed to what RunApp needs).
struct ContextShowPayload: Codable, Sendable {
    struct Effective: Codable, Sendable {
        struct Build: Codable, Sendable {
            let configuration: SourcedValue
            let destination: SourcedValue
            let scheme: SourcedValue
            let sdk: SourcedValue
        }

        let build: Build
    }

    let container: String
    let effective: Effective
    let lastLaunchedApp: LastLaunchedApp?
    // `recentDestinations` exists too, but was only ever observed as `[]`, so its element type is unverified.
}
