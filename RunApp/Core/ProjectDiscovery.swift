import Foundation

/// One buildable thing found under a folder: shown in the project picker.
struct ProjectCandidate: Hashable, Sendable, Identifiable {
    enum Generator: String, Sendable {
        case xcodegen = "XcodeGen"
        case tuist = "Tuist"
    }

    enum Kind: Sendable, Hashable {
        case workspace
        case project
        case package
        /// A Tuist / XcodeGen spec whose `.xcodeproj` hasn't been generated yet.
        case spec(Generator)
    }

    let kind: Kind
    /// The `.xcworkspace`, `.xcodeproj`, `Package.swift`, or spec file.
    let url: URL
    /// Path relative to the folder that was searched, for display and filtering.
    let relativePath: String
    /// Set when the project comes from a spec file next to it.
    let generator: Generator?

    var id: URL {
        url
    }

    var displayName: String {
        switch kind {
        case .workspace, .project: url.deletingPathExtension().lastPathComponent
        case .package, .spec: url.deletingLastPathComponent().lastPathComponent
        }
    }

    var kindLabel: String {
        switch kind {
        case .workspace: "Workspace"
        case .project: "Project"
        case .package: "Package"
        case let .spec(generator): generator.rawValue
        }
    }

    /// `nil` for a spec that still needs generating.
    var located: LocatedProject? {
        switch kind {
        case .workspace: LocatedProject(kind: .workspace, url: url)
        case .project: LocatedProject(kind: .project, url: url)
        case .package: LocatedProject(kind: .package, url: url)
        case .spec: nil
        }
    }

    /// Shell command that generates the project for a `.spec` candidate.
    var generateCommand: String? {
        guard case let .spec(generator) = kind else { return nil }
        let dir = url.deletingLastPathComponent().path
        return switch generator {
        case .xcodegen: "cd \"\(dir)\" && xcodegen generate"
        case .tuist: "cd \"\(dir)\" && tuist generate --no-open"
        }
    }

    /// Case-insensitive match of every whitespace-separated token against name or relative path.
    func matches(_ query: String) -> Bool {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }
        let haystack = "\(displayName) \(relativePath) \(kindLabel)".lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

/// Recursively finds every workspace, project, package and Tuist/XcodeGen spec under a folder.
/// Inside a git repository it uses `git ls-files`, so anything git-ignored (`.build/checkouts`, `DerivedData`, …)
/// is skipped. Generated `.xcodeproj`s are usually git-ignored, so they are found through their spec file instead.
enum ProjectDiscovery {
    static func discover(in root: URL, fileManager: FileManager = .default) async -> [ProjectCandidate] {
        let root = root.standardizedFileURL
        let files = await gitFiles(in: root) ?? walk(root, fileManager: fileManager)
        return candidates(fromRelativePaths: files, root: root, fileManager: fileManager)
    }

    /// Turns a flat file list (paths relative to `root`) into sorted, de-duplicated candidates.
    static func candidates(
        fromRelativePaths files: [String],
        root: URL,
        fileManager: FileManager = .default
    ) -> [ProjectCandidate] {
        var found: [URL: ProjectCandidate] = [:]

        func add(_ kind: ProjectCandidate.Kind, _ relative: String, generator: ProjectCandidate.Generator? = nil) {
            let url = root.appendingPathComponent(relative).standardizedFileURL
            if let existing = found[url], existing.generator != nil {
                return
            }
            found[url] = ProjectCandidate(kind: kind, url: url, relativePath: relative, generator: generator)
        }

        for path in files {
            let name = (path as NSString).lastPathComponent
            let parent = (path as NSString).deletingLastPathComponent
            switch name {
            case "project.pbxproj" where parent.hasSuffix(".xcodeproj"):
                add(.project, parent)
            case "contents.xcworkspacedata" where parent.hasSuffix(".xcworkspace") && !parent.contains(".xcodeproj/"):
                add(.workspace, parent)
            case "Package.swift" where !parent.contains(".xcodeproj/"):
                add(.package, path)
            case "project.yml" where isXcodeGenSpec(root.appendingPathComponent(path)),
                 "project.yaml" where isXcodeGenSpec(root.appendingPathComponent(path)):
                addGenerated(.xcodegen, spec: path, root: root, fileManager: fileManager, add: add)
            case "Project.swift" where isTuistManifest(root.appendingPathComponent(path)):
                addGenerated(.tuist, spec: path, root: root, fileManager: fileManager, add: add)
            default:
                break
            }
        }

        return found.values.sorted { lhs, rhs in
            let lhsDepth = lhs.relativePath.split(separator: "/").count
            let rhsDepth = rhs.relativePath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    /// A spec file: list the workspace/project generated beside it (even if git-ignored), or the spec itself.
    private static func addGenerated(
        _ generator: ProjectCandidate.Generator,
        spec: String,
        root: URL,
        fileManager: FileManager,
        add: (ProjectCandidate.Kind, String, ProjectCandidate.Generator?) -> Void
    ) {
        let dir = (spec as NSString).deletingLastPathComponent
        let entries = ((try? fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)) ?? []).sorted()
        let join = { (name: String) in dir.isEmpty ? name : "\(dir)/\(name)" }
        if let workspace = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            add(.workspace, join(workspace), generator)
        } else if let project = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            add(.project, join(project), generator)
        } else {
            add(.spec(generator), spec, generator)
        }
    }

    /// `project.yml` is common outside Apple projects; XcodeGen specs declare `targets:`.
    private static func isXcodeGenSpec(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("targets:")
    }

    /// `Project.swift` is a Tuist manifest only if it imports ProjectDescription.
    private static func isTuistManifest(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("ProjectDescription")
    }

    // MARK: File listing

    /// Tracked plus untracked-but-not-ignored files under `root`, or `nil` when `root` isn't in a git work tree.
    static func gitFiles(in root: URL) async -> [String]? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                continuation.resume(returning: nil)
                return
            }
            let paths = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
            continuation.resume(returning: paths)
        }
    }

    /// Folders never worth descending into outside git.
    private static let skippedDirectories: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData", "build", ".build", "vendor",
    ]

    /// Fallback for non-git folders: walk the tree, skipping hidden and dependency folders.
    static func walk(_ root: URL, fileManager: FileManager = .default, maxDepth: Int = 8) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if skippedDirectories.contains(name) || enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let relative = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            // Packages aren't descended into, so report the marker file the git path would have listed.
            switch url.pathExtension {
            case "xcodeproj": paths.append(relative + "/project.pbxproj")
            case "xcworkspace": paths.append(relative + "/contents.xcworkspacedata")
            default: paths.append(relative)
            }
        }
        return paths
    }
}
