import Foundation

/// What RunApp should hand to SweetPad for a given path.
struct LocatedProject: Hashable, Sendable {
    enum Kind: String, Sendable {
        case workspace
        case project
        case package
    }

    let kind: Kind
    /// The `.xcworkspace`, `.xcodeproj` or `Package.swift`.
    let url: URL

    /// Folder to run SweetPad in (`sweetpad -C <dir>`).
    var directory: URL {
        url.deletingLastPathComponent()
    }

    var displayName: String {
        kind == .package ? directory.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    /// Target-selection flags for SweetPad. A package relies on SweetPad's auto-discovery in `directory`.
    /// These are subcommand flags: put them **after** the subcommand (`["scheme", "list"] + args`);
    /// `sweetpad --project X scheme list` is a usage error (exit 2).
    var sweetPadArguments: [String] {
        switch kind {
        case .workspace: ["--workspace", url.path]
        case .project: ["--project", url.path]
        case .package: []
        }
    }
}

/// Finds the workspace / project / package for a path: `*.xcworkspace`, then `*.xcodeproj`, then `Package.swift`.
enum ProjectLocator {
    static func locate(_ path: URL, fileManager: FileManager = .default) -> LocatedProject? {
        let url = path.standardizedFileURL
        switch url.pathExtension {
        case "xcworkspace":
            return LocatedProject(kind: .workspace, url: url)
        case "xcodeproj":
            return LocatedProject(kind: .project, url: url)
        default:
            break
        }
        if url.lastPathComponent == "Package.swift" {
            return LocatedProject(kind: .package, url: url)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let entries = ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []).sorted()

        if let workspace = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return LocatedProject(kind: .workspace, url: url.appendingPathComponent(workspace))
        }
        if let project = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return LocatedProject(kind: .project, url: url.appendingPathComponent(project))
        }
        if entries.contains("Package.swift") {
            return LocatedProject(kind: .package, url: url.appendingPathComponent("Package.swift"))
        }
        return nil
    }

    /// Picks the project path out of the app's launch arguments (`arguments[0]` is the executable).
    /// Skips flags and their non-path values, such as `-ApplePersistenceIgnoreState YES` (added by
    /// `sweetpad run`) and `-NSDocumentRevisionsDebugMode YES` (added by Xcode).
    static func pathArgument(from arguments: [String]) -> URL? {
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            index += 1
            if arg.hasPrefix("-") {
                if index < arguments.count, !arguments[index].hasPrefix("-"), !arguments[index].hasPrefix("/") {
                    index += 1 // flag value
                }
                continue
            }
            return URL(fileURLWithPath: arg)
        }
        return nil
    }
}
