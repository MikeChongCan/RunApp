import Foundation
@testable import RunApp
import Testing

/// Fixtures are trimmed real output from sweetpad 0.1.14 (see docs/sweetpad-cli.md).
struct SweetPadDecodingTests {
    @Test func decodesDevicesEnvelope() throws {
        let json = """
        {"data":{"destinations":[
          {"booted":null,"connection":null,"destination":"platform=macOS","kind":"macOS","name":"My Mac",
           "os":"macOS","osVersion":"","pairing":null,"transport":null,"udid":null},
          {"booted":true,"connection":null,"destination":"platform=iOS Simulator,id=8B1C39FD-868E-400E-8308-3D5E4B80C8EC",
           "kind":"simulator","name":"iPhone Duo","os":"iOS","osVersion":"27.1","pairing":null,"transport":null,
           "udid":"8B1C39FD-868E-400E-8308-3D5E4B80C8EC"},
          {"booted":null,"connection":"disconnected","destination":"platform=iOS,id=00008140-00105944367B001C","kind":"device",
           "name":"Alex-iPhone","os":"iOS","osVersion":"27.0.1","pairing":"paired","transport":"localNetwork",
           "udid":"00008140-00105944367B001C"},
          {"booted":null,"connection":"connected","destination":"platform=iOS,id=00008030-001570642198802E","kind":"device",
           "name":"Personal iPhone","os":"iOS","osVersion":"18.6","pairing":"paired","transport":"wired",
           "udid":"00008030-001570642198802E"}
        ]},"ok":true,"schema":1}
        """
        let envelope = try SweetPadClient.decodeEnvelope(DevicesPayload.self, from: Data(json.utf8))
        #expect(envelope.ok)
        #expect(envelope.schema == 1)
        let destinations = try #require(envelope.data?.destinations)
        #expect(destinations.map(\.kind) == [.mac, .simulator, .wifi, .usb])
        #expect(destinations[0].onArgument == "mac")
        #expect(destinations[1].onArgument == "8B1C39FD-868E-400E-8308-3D5E4B80C8EC")
        #expect(destinations[1].isAvailable)
        #expect(!destinations[2].isAvailable)
        #expect(destinations[3].isAvailable)
    }

    @Test func decodesErrorEnvelopeFromStderr() {
        let stderr = #"{"error":{"code":"target_resolution","message":"unknown scheme \"Nope\" (schemes: SampleApp)"},"#
            + #""ok":false,"schema":1}"#
        let output = ProcessOutput(exitCode: 4, stdout: Data(), stderr: Data(stderr.utf8))
        #expect(throws: SweetPadClientError.self) {
            try SweetPadClient.decodePayload(SchemeListPayload.self, from: output)
        }
        let error = SweetPadClient.decodeError(from: output)
        #expect(error?.code == "target_resolution")
    }

    @Test func parsesNDJSONBuildStream() {
        let lines = [
            #"{"event":"task","kind":"compile","name":"ContentView.swift"}"#,
            #"{"event":"diagnostic","location":"/tmp/App/ContentView.swift:19:16","message":"never used","severity":"warning"}"#,
            #"{"data":{"built":true,"configuration":"Debug","destination":"platform=macOS","durationMs":2711,"errors":0,"#
                + #""productPath":"/tmp/App.app","scheme":"App","warnings":1},"event":"result","ok":true}"#,
        ]
        let splitter = LineSplitter()
        let joined = Data(lines.joined(separator: "\n").utf8)
        let parsed = (splitter.feed(joined.prefix(30)) + splitter.feed(joined.dropFirst(30)) + splitter.flush())
            .compactMap(BuildEvent.parse(line:))
        #expect(parsed.count == 3)
        #expect(parsed[0] == .task(kind: "compile", name: "ContentView.swift"))
        guard case let .result(result) = parsed[2] else {
            Issue.record("expected result")
            return
        }
        #expect(result.ok)
        #expect(result.data?.built == true)
        #expect(result.data?.warnings == 1)
    }
}

struct ProjectLocatorTests {
    @Test func prefersWorkspaceOverProjectOverPackage() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("RunAppTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("Package.swift").path, contents: Data())
        #expect(ProjectLocator.locate(root)?.kind == .package)

        try fm.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        #expect(ProjectLocator.locate(root)?.kind == .project)

        try fm.createDirectory(at: root.appendingPathComponent("App.xcworkspace"), withIntermediateDirectories: true)
        let found = try #require(ProjectLocator.locate(root))
        #expect(found.kind == .workspace)
        #expect(found.url.lastPathComponent == "App.xcworkspace")
        #expect(found.sweetPadArguments.first == "--workspace")
    }

    @Test func pathArgumentSkipsLaunchFlags() {
        let args = ["/Applications/RunApp.app/Contents/MacOS/RunApp", "-ApplePersistenceIgnoreState", "YES", "/Users/me/Code/App"]
        #expect(ProjectLocator.pathArgument(from: args)?.path == "/Users/me/Code/App")
        #expect(ProjectLocator.pathArgument(from: ["/x/RunApp"]) == nil)
    }
}
