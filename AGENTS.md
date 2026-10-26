# AGENTS.md — RunApp

RunApp is a small, native **SwiftUI macOS app** that builds and runs Xcode projects without opening Xcode.
Open a project from Terminal the way `xed .` does, choose a **scheme** and a **destination** (this Mac, a
USB or Wi‑Fi device, or a simulator), then press **Play**. Under the hood it calls the
[SweetPad CLI](https://github.com/sweetpad-dev/sweetpad), plus Xcode's own command-line tools where needed.

- License: MIT · open source on GitHub
- Platform: macOS 15+ (Apple silicon and Intel), Swift 6, SwiftUI
- Design mockups: `design/` (canvas source: `canvas.json` + `*.dc.html`), live at https://claude.ai/artifact/GXx2pBB9TquR41AfAnPnea

## Product scope

| Feature | How |
| --- | --- |
| `runapp .` / `runapp path/to/App.xcodeproj` | Small CLI shim that opens the app via `open -a RunApp --args <path>` (same idea as `xed`) |
| Find project | Look in the folder for `*.xcworkspace`, then `*.xcodeproj`, then `Package.swift` (SweetPad also handles Tuist and XcodeGen) |
| Scheme list | `sweetpad scheme list -o json` |
| Configurations | `sweetpad project info -o json` → `data.configurations`; pass `--configuration <C>` |
| Device discovery: Mac, USB, Wi‑Fi, simulators | `sweetpad devices -o json` → `data.destinations[]` (`kind`: `macOS`/`simulator`/`device`; USB vs Wi‑Fi is `transport`: `wired`/`localNetwork`); extra details from `sweetpad device list` and `sweetpad simulator list` |
| Play | `sweetpad run --scheme <S> --on <UDID or mac> --detach --non-interactive -o ndjson` (builds, launches, returns `pid`), then follow `sweetpad app logs --non-interactive -o ndjson`. Plain `run -o ndjson` without `--detach`/`--no-logs` is refused (exit 2) |
| Stop | `sweetpad app stop -o json`, then SIGTERM the logs process. SIGTERM to `sweetpad run` does **not** stop the app |
| Live build log | Parse the NDJSON stream: `event: task` lines show progress, `event: diagnostic` lines carry errors and warnings, and the last `event: result` line is the outcome |
| Errors | Use the exit code: `3` = build failed, `4` = unknown scheme or device, `5` = a required tool is missing (show onboarding) |
| Remembered choices | SweetPad saves them per project (`sweetpad status`, `sweetpad context …`). Don't copy them into RunApp's own state |

Out of scope for v1: source editing, Interface Builder, archive and upload, and test UI.

## Onboarding (new contributor)

```bash
# 1. Xcode (full app, not just the Command Line Tools) and license
xcode-select -p                      # should point inside Xcode.app
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch

# 2. Homebrew
command -v brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. SweetPad CLI (RunApp's build/run engine)
brew install sweetpad-dev/tap/sweetpad
sweetpad --version
# alternative: mise use -g 'github:sweetpad-dev/sweetpad[version_prefix=cli-v]'

# 4. Dev tools for this repo
brew install xcodegen swiftformat swiftlint xcbeautify

# 5. Sanity check: list what SweetPad can see
sweetpad devices
```

Physical devices: connect over USB once, tap **Trust**, and turn on **Developer Mode**
(Settings › Privacy & Security). After that, Wi‑Fi devices show up as long as they're on the same network.
Run `sweetpad device info` to check that a device is ready.

## Build and run RunApp itself

The project is generated from `project.yml` (XcodeGen). Don't commit or hand-edit `RunApp.xcodeproj`.

```bash
xcodegen generate                    # creates RunApp.xcodeproj
sweetpad run --scheme RunApp --on mac        # build + launch RunApp, stream logs (r = rebuild, q = quit)
sweetpad build --scheme RunApp --on mac -o quiet   # fast check that it compiles
sweetpad test  --scheme RunApp --on mac      # unit tests
```

Without SweetPad:

```bash
xcodebuild -project RunApp.xcodeproj -scheme RunApp -destination 'platform=macOS' build | xcbeautify
```

Install the `runapp` shim for local testing:

```bash
ln -sf "$PWD/Scripts/runapp" /usr/local/bin/runapp   # or ~/.local/bin
runapp ~/Code/SomeiOSApp
```

## Repo layout (target)

```
project.yml                 XcodeGen spec
RunApp/
  App/                      @main RunAppApp, AppDelegate (handles open-file / args)
  Features/
    Toolbar/                Play/Stop, scheme + destination pickers, status capsule
    Sidebar/                Project, schemes, configuration, device groups
    Console/                Build / app output / device log tabs
    Onboarding/             Toolchain check (Xcode, brew, sweetpad)
  Core/
    SweetPad/               SweetPadClient: runs the process, decodes JSON/NDJSON envelopes
    Models/                 Scheme, Destination (kind: mac|usb|wifi|simulator), BuildEvent
    ProjectLocator.swift    Finds workspace/project/package from a path
Scripts/runapp              CLI shim (`open -a RunApp --args <abs path>`; `open -a RunApp <path>` if already running)
RunAppTests/                Swift Testing unit tests
docs/sweetpad-cli.md        Observed SweetPad JSON/NDJSON shapes
```

## Conventions for agents

- **Shell out only through `SweetPadClient`** (`Process` + async `AsyncStream<BuildEvent>`). Always pass
  `-o json`, or `-o ndjson` for build/test/`run --detach`/`app logs`, plus `--non-interactive`. Never scrape the human-readable output.
- Decode the envelope `{schema, ok, data | error}`. `ok: true` only means the command ran. Check the
  payload too (for example `data.built`, `data.passed`). With `-o json`, errors go to **stderr**.
- Target flags (`--project`, `--workspace`, `--scheme`, `--on`, `--configuration`) go **after** the subcommand.
  Global flags (`-C <dir>`, `-o`) can go anywhere.
- Real JSON shapes, flags, and exit codes are in [docs/sweetpad-cli.md](docs/sweetpad-cli.md). Update that file when SweetPad changes.
- Find the `sweetpad` binary in this order: `$RUNAPP_SWEETPAD`, `/opt/homebrew/bin`, `/usr/local/bin`, `$PATH`.
  If it's missing (exit 5), show onboarding instead of crashing.
- SwiftUI + Observation (`@Observable`). Use Swift 6 strict concurrency and keep UI state on `@MainActor`.
  Don't add third-party Swift packages without a reason recorded in the PR.
- The UI should feel like a native Mac app: use system font, system colors, and SF Symbols, follow light/dark mode, and support keyboard
  shortcuts (⌘R Run, ⌘. Stop, ⌘⇧K Clean, ⌘⇧R Refresh devices).
- The app is not sandboxed, because it has to spawn `xcodebuild` and `sweetpad`. Distribute it as a Developer ID build with
  notarization, not through the Mac App Store. Local builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`), and Xcode
  drops Hardened Runtime for those builds. It applies once the build is signed with a real identity.
- Before you finish a change: `swiftformat . && swiftlint && sweetpad build --scheme RunApp --on mac -o quiet && sweetpad test --scheme RunApp --on mac`.
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:` …). Don't commit generated `.xcodeproj` or `DerivedData`.

## Agent skills

Run `Scripts/install-skills` once after cloning. It restores the skills pinned in `skills-lock.json` and exports
Xcode's own skills (`xcrun mcpbridge run-agent skills export`) into `.agents/skills/`, symlinked into
`.claude/skills/`. Both folders are git-ignored. Use them:

- SwiftUI views: `swiftui-pro`, `swiftui-expert-skill`, Xcode's `swiftui-specialist` / `swiftui-whats-new-27`
- Concurrency (`SweetPadClient`, `Process`, streams): `swift-concurrency`
- Tests: `swift-testing-expert`, Xcode's `modernize-tests`
- Windows, menus, AppKit interop: `macos-patterns`, Xcode's `app-resizability`
- Accessibility: `ios-accessibility`. Release: `asc-notarization`, Xcode's `audit-xcode-security-settings`

Add a skill with `npx skills add <owner/repo> -s <skill> -a claude-code opencode codex -y`, then commit `skills-lock.json`.

## References

- SweetPad CLI docs: https://sweetpad.hyzyla.dev/docs/cli/getting-started
  (destinations, scripts and CI / exit codes, agent skills)
- `xcrun devicectl help`, `xcrun simctl help`: lower-level fallbacks
