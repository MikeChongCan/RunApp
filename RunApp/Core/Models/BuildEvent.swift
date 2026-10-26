import Foundation

/// One line of `-o ndjson` output from `sweetpad build|run --no-logs|test`.
///
/// Observed lines (sweetpad 0.1.14):
/// ```
/// {"event":"task","kind":"compile","name":"ContentView.swift"}
/// {"event":"diagnostic","severity":"error","message":"…","location":"/abs/File.swift:19:14"}
/// {"event":"result","ok":true,"data":{"built":true,"warnings":1,…}}
/// {"event":"result","ok":false,"error":{"code":"build_failure","message":"…","diagnostics":[…]}}
/// ```
enum BuildEvent: Sendable, Equatable {
    /// `kind` seen so far: compile, link, copy, codesign, plist (treat as free text).
    case task(kind: String, name: String)
    case diagnostic(Diagnostic)
    case result(ResultLine)
    /// Any other `event` value, kept raw so new SweetPad versions don't break the stream.
    case other(event: String, raw: Data)

    /// Parses one NDJSON line. Returns `nil` for blank or non-JSON lines.
    static func parse(line: Data) -> BuildEvent? {
        let decoder = JSONDecoder()
        guard let head = try? decoder.decode(Head.self, from: line) else {
            return nil
        }
        switch head.event {
        case "task":
            guard let task = try? decoder.decode(TaskLine.self, from: line) else {
                return .other(event: head.event, raw: line)
            }
            return .task(kind: task.kind, name: task.name)
        case "diagnostic":
            guard let diagnostic = try? decoder.decode(Diagnostic.self, from: line) else {
                return .other(event: head.event, raw: line)
            }
            return .diagnostic(diagnostic)
        case "result":
            guard let result = try? decoder.decode(ResultLine.self, from: line) else {
                return .other(event: head.event, raw: line)
            }
            return .result(result)
        default:
            return .other(event: head.event, raw: line)
        }
    }

    private struct Head: Decodable {
        let event: String
    }

    private struct TaskLine: Decodable {
        let kind: String
        let name: String
    }
}

/// A compiler diagnostic. Also appears inside `error.diagnostics` of a failed build.
struct Diagnostic: Codable, Sendable, Hashable {
    /// `"error"` or `"warning"` (possibly `"note"`).
    let severity: String
    let message: String
    /// `"/abs/path/File.swift:line:column"`; may be absent for project-level issues.
    let location: String?
}

/// The final `{"event":"result", …}` line of an NDJSON stream.
struct ResultLine: Decodable, Sendable, Equatable {
    let ok: Bool
    let data: ResultData?
    let error: SweetPadErrorPayload?
}

/// Union of the `data` fields seen in build and run results. All optional: which ones are present
/// depends on the command.
struct ResultData: Codable, Sendable, Equatable {
    // build
    let built: Bool?
    let configuration: String?
    let destination: String?
    let durationMs: Int?
    let errors: Int?
    let warnings: Int?
    let productPath: String?
    let scheme: String?
    // run --no-logs / --detach
    let bundleId: String?
    let detached: Bool?
    let pid: Int?
    // test (`sweetpad test -o json` data; `failures` omitted until its shape is observed)
    let passed: Bool?
    let passedTests: Int?
    let failedTests: Int?
    let skippedTests: Int?
    let total: Int?
    let resultBundle: String?
}
