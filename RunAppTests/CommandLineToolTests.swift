import Foundation
@testable import RunApp
import Testing

struct CommandLineToolTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func statusWhenNothingIsLinked() throws {
        let dir = try tempDir()
        let status = CommandLineTool.status(link: dir.appendingPathComponent("runapp").path, script: "/x/runapp")
        #expect(status == .notInstalled)
    }

    @Test func installLinksToTheScriptAndReportsInstalled() async throws {
        let dir = try tempDir()
        let script = dir.appendingPathComponent("RunApp.app/Contents/Resources/runapp")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: script)
        let link = dir.appendingPathComponent("bin/runapp").path

        #expect(try await CommandLineTool.install(script: script.path, link: link))
        #expect(CommandLineTool.status(link: link, script: script.path) == .installed)
    }

    @Test func installReplacesALinkToAnotherCopy() async throws {
        let dir = try tempDir()
        let link = dir.appendingPathComponent("runapp").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Old/RunApp.app/Contents/Resources/runapp")
        #expect(CommandLineTool.status(link: link, script: "/New/runapp") == .other("/Old/RunApp.app/Contents/Resources/runapp"))

        #expect(try await CommandLineTool.install(script: "/New/runapp", link: link))
        #expect(CommandLineTool.status(link: link, script: "/New/runapp") == .installed)
    }
}
