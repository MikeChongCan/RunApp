import Foundation

/// The one-shot `-o json` envelope: `{"schema": 1, "ok": true, "data": {…}}` on **stdout**, or
/// `{"schema": 1, "ok": false, "error": {"code": …, "message": …}}` on **stderr**.
///
/// `ok: true` only means the command ran. Check the payload's own status field too
/// (`data.built`, `data.passed`).
struct SweetPadEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let schema: Int
    let ok: Bool
    let data: Payload?
    let error: SweetPadErrorPayload?
}

/// `error` object of a failed command.
struct SweetPadErrorPayload: Codable, Sendable, Equatable, Error {
    /// `generic`, `usage_error`, `build_failure`, `target_resolution`, `tool_missing`, `user_cancel`.
    let code: String
    let message: String
    /// Present on `build_failure`.
    let diagnostics: [Diagnostic]?
}

/// Process exit codes (`sweetpad help exit-codes`).
enum SweetPadExitCode: Int32, Sendable {
    case success = 0
    case generic = 1
    case usage = 2
    case buildOrTestFailure = 3
    case targetResolution = 4
    case toolMissing = 5
    case cancelled = 6
    /// Killed by SIGINT (128 + 2).
    case interrupted = 130
    /// Killed by SIGTERM (128 + 15).
    case terminated = 143
}

/// `data` of `sweetpad app stop -o json`: `{"action":"terminated","bundleId":…,"detail":null,"pid":58748|null,"udid":null|"<sim>"}`.
struct AppStopPayload: Codable, Sendable {
    let action: String
    let bundleId: String?
    let detail: String?
    let pid: Int?
    let udid: String?
}

/// For commands whose `data` RunApp doesn't care about (e.g. `app stop`).
struct EmptyPayload: Codable, Sendable {}
