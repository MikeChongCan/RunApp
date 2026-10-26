import Foundation
@testable import RunApp
import Testing

struct ProjectDiscoveryTests {
    /// Builds a throwaway tree under the temp dir and returns its root.
    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunAppTests-\(UUID().uuidString)", isDirectory: true)
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        return root
    }

    @Test func findsProjectsPackagesAndSkipsEmbeddedWorkspace() throws {
        let root = try makeTree([
            "apps/QCam/QCam.xcodeproj/project.pbxproj": "",
            "apps/CamQ/CamQ.xcworkspace/contents.xcworkspacedata": "",
            "apps/CamQ/CamQ.xcodeproj/project.pbxproj": "",
            "apps/QCam/Packages/Core/Package.swift": "",
            "packages/Nova/Package.swift": "",
        ])
        let files = [
            "apps/QCam/QCam.xcodeproj/project.pbxproj",
            "apps/QCam/QCam.xcodeproj/project.xcworkspace/contents.xcworkspacedata",
            "apps/CamQ/CamQ.xcworkspace/contents.xcworkspacedata",
            "apps/CamQ/CamQ.xcodeproj/project.pbxproj",
            "apps/QCam/Packages/Core/Package.swift",
            "packages/Nova/Package.swift",
            "README.md",
        ]
        let found = ProjectDiscovery.candidates(fromRelativePaths: files, root: root)
        #expect(found.map(\.relativePath) == [
            "apps/CamQ/CamQ.xcodeproj",
            "apps/CamQ/CamQ.xcworkspace",
            "apps/QCam/QCam.xcodeproj",
            "packages/Nova/Package.swift",
            "apps/QCam/Packages/Core/Package.swift",
        ])
        #expect(found.first { $0.relativePath == "apps/QCam/QCam.xcodeproj" }?.displayName == "QCam")
        #expect(found.first { $0.kind == .package }?.displayName == "Nova")
    }

    @Test func specFindsIgnoredGeneratedProjectOrNeedsGeneration() throws {
        let root = try makeTree([
            "Gen/project.yml": "name: Gen\ntargets:\n  Gen: {}\n",
            "Gen/Gen.xcodeproj/project.pbxproj": "",
            "Hyper/Project.swift": "import ProjectDescription\n",
            "Other/project.yml": "services: {}\n",
        ])
        // Generated .xcodeproj is git-ignored, so only spec files are listed.
        let found = ProjectDiscovery.candidates(
            fromRelativePaths: ["Gen/project.yml", "Hyper/Project.swift", "Other/project.yml"],
            root: root
        )
        #expect(found.count == 2)
        let gen = try #require(found.first { $0.relativePath == "Gen/Gen.xcodeproj" })
        #expect(gen.generator == .xcodegen)
        #expect(gen.located?.kind == .project)
        let hyper = try #require(found.first { $0.relativePath == "Hyper/Project.swift" })
        #expect(hyper.kind == .spec(.tuist))
        #expect(hyper.located == nil)
        #expect(hyper.generateCommand?.hasSuffix("tuist generate --no-open") == true)
    }

    @Test func walkFallbackSkipsDependencyFolders() throws {
        let root = try makeTree([
            "App/App.xcodeproj/project.pbxproj": "",
            "App/Pods/Dep/Dep.xcodeproj/project.pbxproj": "",
            "node_modules/x/Package.swift": "",
            "Lib/Package.swift": "",
        ])
        let found = ProjectDiscovery.candidates(fromRelativePaths: ProjectDiscovery.walk(root), root: root)
        #expect(Set(found.map(\.relativePath)) == ["App/App.xcodeproj", "Lib/Package.swift"])
    }

    @Test func filterMatchesAllTokens() {
        let candidate = ProjectCandidate(
            kind: .project,
            url: URL(fileURLWithPath: "/r/apps/QCam/QCam.xcodeproj"),
            relativePath: "apps/QCam/QCam.xcodeproj",
            generator: nil
        )
        #expect(candidate.matches(""))
        #expect(candidate.matches("qcam apps"))
        #expect(candidate.matches("project"))
        #expect(!candidate.matches("qcam package"))
    }
}
