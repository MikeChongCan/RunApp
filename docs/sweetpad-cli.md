# SweetPad CLI: observed behavior

Captured from **sweetpad 0.1.14** (Homebrew, `sweetpad-dev/tap/sweetpad`), Xcode 27.1, macOS 26, on 2026-10-26,
against throwaway apps made with `sweetpad project new` (iOS and macOS). Paths and IDs are trimmed. These are the shapes
the Swift models in `RunApp/Core/Models` and `RunApp/Core/SweetPad` decode. Re-check them when you bump SweetPad.

## General rules

- **Envelope** (`-o json`): `{"schema": 1, "ok": true, "data": {…}}` on **stdout**, exit 0.
- **Errors** (`-o json`): `{"schema":1,"ok":false,"error":{"code":…,"message":…}}` on **stderr**, and stdout is empty.
  `code` is one of `generic`, `usage_error`, `build_failure`, `target_resolution`, `tool_missing`, `user_cancel`.
  A flag that clap can't parse prints plain clap text (not JSON) to stderr with exit 2.
- **NDJSON** (`-o ndjson`, for build/test/run --no-logs/--detach and app logs): one compact object per line on stdout.
  The last line is `{"event":"result","ok":…,"data"|"error":…}`. On failure the error envelope is **also** printed to stderr.
- `ok: true` only means the command ran. Read `data.built` / `data.passed`.
- Always pass `--non-interactive` (or set `SWEETPAD_NONINTERACTIVE=1`). Without it, a missing scheme or destination
  opens a picker. With it, you get exit 4: `"no destination specified and the terminal is not interactive; …"`.
- **Flag order:** global flags (`-C <dir>`, `-o`, `--non-interactive`, `--developer-dir`) go anywhere. Target-selection flags
  (`--workspace`, `--project`, `--scheme`, `--configuration`, `--on`, `--destination`) are **subcommand** flags and must come
  after the subcommand. `sweetpad --project X scheme list` is a usage error (exit 2).
- Key casing: camelCase everywhere, **except** `lastLaunchedApp` in `status` / `context show`, which uses snake_case keys.
- Keys print in alphabetical order (pretty JSON for `-o json`, compact for ndjson).

### Exit codes (`sweetpad help exit-codes`)

| code | meaning |
| --- | --- |
| 0 | success |
| 1 | generic failure (also: `run` built the app but it didn't launch) |
| 2 | usage error (bad flags, or a flag/mode the command refuses) |
| 3 | build or test failure |
| 4 | target resolution failed (unknown scheme, destination, simulator, or device) |
| 5 | a required tool is missing (xcodebuild, simctl, …) |
| 6 | cancelled by the user |
| 130 / 143 | killed by SIGINT / SIGTERM |

## Destinations: `sweetpad devices -o json`

`data.destinations[]`, ordered most-used first (per project), then booted ones, then platform/OS. Every entry has the
same keys. Keys that don't apply are `null`.

```json
{"data":{"destinations":[
  {"booted":null,"connection":null,"destination":"platform=macOS","kind":"macOS","name":"My Mac",
   "os":"macOS","osVersion":"","pairing":null,"transport":null,"udid":null},
  {"booted":true,"connection":null,"destination":"platform=iOS Simulator,id=8B1C39FD-…","kind":"simulator",
   "name":"iPhone Duo","os":"iOS","osVersion":"27.1","pairing":null,"transport":null,"udid":"8B1C39FD-…"},
  {"booted":null,"connection":"disconnected","destination":"platform=iOS,id=00008140-…","kind":"device",
   "name":"Alex-iPhone","os":"iOS","osVersion":"27.0.1","pairing":"paired","transport":"localNetwork","udid":"00008140-…"},
  {"booted":null,"connection":"disconnected","destination":"platform=iOS,id=00008030-…","kind":"device",
   "name":"Personal iPhone 11 PM","os":"iOS","osVersion":"18.6","pairing":"paired","transport":"wired","udid":"00008030-…"}
]},"ok":true,"schema":1}
```

- `kind`: `"macOS"` | `"simulator"` | `"device"`. There is no `usb` or `wifi` kind.
- **USB vs Wi‑Fi:** `transport` (devicectl's `transportType`): `"wired"` = USB, `"localNetwork"` = Wi‑Fi. `""` was seen on
  a device that was never reachable (`connection: "unavailable"`). `transport` keeps the last-known value even when the
  device is disconnected.
- `connection` (devicectl tunnel state): seen `"disconnected"`, `"unavailable"`. **`"connected"` is expected for a live
  device, but no device was connected during capture, so that value is unverified.**
- `pairing`: `"paired"`.
- `os` covers tvOS/watchOS devices too (paired Apple TV and Watch show up). Filter by the scheme's platform if needed.
- `osVersion` is `""` for My Mac.
- For `--on`, pass `mac` for the Mac, otherwise the `udid`. Fuzzy names work too, but they're ambiguous.
- RunApp mapping (`Destination.kind`): macOS→`.mac`, simulator→`.simulator`, device+`localNetwork`→`.wifi`, other device→`.usb`.

### `sweetpad device list -o json` (paired physical devices)

```json
{"data":{"devices":[
  {"connection":"disconnected","model":"iPhone 16 Pro","name":"Alex-iPhone","osVersion":"27.0.1",
   "pairing":"paired","platform":"iOS","transport":"localNetwork","udid":"00008140-…"},
  {"connection":"unavailable","model":"iPad mini (6th generation)","name":"MiniPad","osVersion":"27.2",
   "pairing":"paired","platform":"iOS","transport":"","udid":"00008110-…"}
]},"ok":true,"schema":1}
```

This adds `model` and uses `platform` where `devices` uses `os`. `sweetpad device info` checks whether a device is ready (not captured).

### `sweetpad simulator list -o json`

```json
{"data":{"simulators":[
  {"booted":true,"name":"iPhone Duo","os":"iOS","osVersion":"27.1","state":"Booted","udid":"8B1C39FD-…"},
  {"booted":false,"name":"iPhone 17","os":"iOS","osVersion":"27.0","state":"Shutdown","udid":"75BC7852-…"}
]},"ok":true,"schema":1}
```

## Project

`sweetpad scheme list -o json`:

```json
{"data":{"container":"/…/SampleApp/SampleApp.xcodeproj","schemes":[{"name":"SampleApp","selected":false}],"selected":null},
 "ok":true,"schema":1}
```

`sweetpad project info -o json` (the source for the configuration picker):

```json
{"data":{"configurations":["Debug","Release"],"kind":"project","name":"SampleApp","path":"/…/SampleApp.xcodeproj",
 "schemes":["SampleApp"],"targets":["SampleApp"]},"ok":true,"schema":1}
```

`sweetpad status -o json` (the effective context; `source` is `null` when unset):

```json
{"data":{"container":"/…/MacSample.xcodeproj",
  "context":{"configuration":{"source":"default","value":"Debug"},
             "destination":{"source":"remembered","value":"platform=macOS"},
             "scheme":{"source":"remembered","value":"MacSample"}},
  "detachedLog":null,"kind":"project",
  "lastLaunchedApp":{"app_name":"MacSample.app","app_path":"/…/Debug/MacSample.app","bundle_identifier":"com.example.MacSample",
    "configuration":"Debug","destination":"platform=macOS","executable_name":"MacSample","kind":"macos","scheme":"MacSample"}},
 "ok":true,"schema":1}
```

`sweetpad context show -o json` has `build`, `testing`, `effective.{build,testing}.{configuration,destination,scheme,sdk|target}`
as `{source,value}`, plus `lastLaunchedApp` and `recentDestinations` (only ever seen as `[]`). Observed `source` values:
`default`, `remembered`, `build remembered`, `scheme`, `null`. A successful build or run remembers scheme and destination.

## Build: `sweetpad build --scheme S --on <udid|mac> --non-interactive -o ndjson`

`--configuration Debug|Release` is accepted by build, run, test, and the app subcommands.

```
{"event":"task","kind":"compile","name":"ContentView.swift"}
{"event":"task","kind":"link","name":"__preview.dylib"}
{"event":"task","kind":"plist","name":"Info.plist"}
{"event":"task","kind":"copy","name":"SampleApp.abi.json"}
{"event":"task","kind":"codesign","name":"SampleApp.debug.dylib"}
{"event":"diagnostic","location":"/…/ContentView.swift:19:16","message":"initialization of variable 'unused' was never used; …","severity":"warning"}
{"data":{"built":true,"configuration":"Debug","destination":"platform=iOS Simulator,id=75BC…","durationMs":2711,"errors":0,
 "productPath":"/…/Debug-iphonesimulator/SampleApp.app","scheme":"SampleApp","warnings":1},"event":"result","ok":true}
```

Failure (exit 3). The same error object is also printed to stderr as a full envelope:

```
{"event":"diagnostic","location":"/…/ContentView.swift:19:14","message":"cannot convert value of type 'String' to specified type 'Int'","severity":"error"}
{"error":{"code":"build_failure","diagnostics":[{"event":"diagnostic","location":"…","message":"…","severity":"error"}],
 "message":"building the project: xcodebuild exited with a non-zero status"},"event":"result","ok":false}
```

Under `-o json`, the failure message also names the full log: `…; full log: ~/.local/state/sweetpad/results/<proj>-<hash>-build.log`.

Target errors (exit 4, stderr):

```json
{"error":{"code":"target_resolution","message":"unknown scheme \"Nope\" (schemes: SampleApp)"},"ok":false,"schema":1}
{"error":{"code":"target_resolution","message":"--on \"Nonexistent Phone\" matches nothing (try one of: ATV, …)"},"ok":false,"schema":1}
```

`sweetpad clean` takes `--scheme` and `--configuration` but **not** `--on` (exit 2).

## Run, logs, stop

**`sweetpad run … -o ndjson` (or `-o json`) without `--no-logs` or `--detach` is refused** with exit 2:

```json
{"error":{"code":"usage_error","message":"this 'app run' streams a live session and has no machine-readable form; add '--no-logs' (build, install, launch, and exit) or '--detach', or use 'build start -o ndjson', 'app install'/'app launch --json', and 'app logs -o ndjson' as separate steps"},"event":"result","ok":false}
```

Machine-readable Play is therefore two processes:

1. `sweetpad run --scheme S --on <udid|mac> [--configuration C] --detach --non-interactive -o ndjson`
   streams the same `task`/`diagnostic` events as build, then returns:
   ```
   {"data":{"built":true,"bundleId":"com.example.MacSample","destination":"platform=macOS","detached":true,"pid":58748},"event":"result","ok":true}
   ```
   On macOS, `--detach` starts the app in its own session and captures its stdout/stderr to a log file. On a simulator or
   device it behaves like `--no-logs`. `--no-logs` also works (`"detached":false`). Prefer `--detach` on macOS, so the
   app doesn't depend on sweetpad's pipes.
2. `sweetpad app logs --non-interactive -o ndjson` follows the last-launched app until it gets a signal. SIGTERM exits 0.
   - macOS, stdout/stderr source: `{"eventMessage":"RUNAPP_HELLO_STDOUT","source":"stdout","timestamp":"16:17:31.583"}`
     (NSLog lines come through here too, with their own date prefix).
   - macOS os_log, and simulators: raw `log stream --style json` objects. Useful keys are `eventMessage`, `messageType`
     (`Default`/`Info`/`Debug`/`Error`/`Fault`), `subsystem`, `category`, `processID`, and `timestamp`
     (`"2026-10-26 16:24:21.494886-0600"`). `source` is `null`. Treat any line with an `eventMessage` as a log line.
   - Flags: `--level default|info|debug`, `--subsystem`, `--category`, `--predicate`, `--source oslog|stdout|both`,
     `--last 2m` (print history and exit), `--until TEXT`, `--timeout 30s`, `--exits`.
   - Physical-device log output was not captured.

**Stop:** `sweetpad app stop --non-interactive -o json` (it uses the last-launched app; pass `--scheme/--on` to be explicit):

```json
{"data":{"action":"terminated","bundleId":"com.example.MacSample","detail":null,"pid":58748,"udid":null},"ok":true,"schema":1}
{"data":{"action":"terminated","bundleId":"com.example.SampleApp","detail":null,"pid":null,"udid":"8B1C39FD-…"},"ok":true,"schema":1}
```

**Sending SIGTERM to `sweetpad run` does not stop the app.** In a test, the human-mode
`sweetpad run --non-interactive` exited 143 and the macOS app kept running. Always call `app stop`, and cancel the logs
process as well.

Human-mode `sweetpad run --non-interactive` (no `-o`) does follow the logs as plain text, with no r/q session
(`Running com.example.MacSample (Ctrl-C to stop)` followed by the app's output). Don't parse it.

Other `run` flags: `--arg <ARG>` (repeatable), `--env K=V`, `--wait-for-debugger`, `--restore-state` (by default macOS apps
launch with `-ApplePersistenceIgnoreState YES`), `--hot`/`--no-hot`, `--device`, `--device-id`, `--mac`, `--destination`,
`--sdk`, and `-- <xcodebuild args>`.

## Test: `sweetpad test --scheme S --on mac -o json`

```json
{"data":{"failedTests":0,"failures":[],"lineCoverage":null,"passed":true,"passedTests":5,
 "resultBundle":"~/.local/state/sweetpad/results/RunApp-<hash>.xcresult","skippedTests":0,"total":5},"ok":true,"schema":1}
```

A failing suite exits 3 with `ok: true, data.passed: false` (per the docs; not captured).

## `sweetpad project new`

`sweetpad project new <Name> [--platform ios|macos] [--bundle-id] [--deployment-target] [--no-git] [--current-dir] -o json`
writes a minimal SwiftUI app (xcodeproj plus a shared scheme) without asking questions. Its data has `bundleId`, `files`,
`name`, `path`, `platform`, `scheme`, and `xcodeproj`.
