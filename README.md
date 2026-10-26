# RunApp

A small native SwiftUI macOS app that builds and runs Xcode projects without opening Xcode.
Type `runapp .` in a project folder, pick a scheme and a destination (this Mac, a USB or Wi‑Fi device, or a simulator),
then press **Play**. Under the hood it uses the [SweetPad CLI](https://github.com/sweetpad-dev/sweetpad).

Status: early skeleton. MIT licensed.

## Requirements

- macOS 15 or later, with Xcode installed (the full app, not just the Command Line Tools)
- SweetPad CLI: `brew install sweetpad-dev/tap/sweetpad`

## Install the `runapp` command

```bash
ln -sf "$PWD/Scripts/runapp" /usr/local/bin/runapp   # or anywhere on your PATH
runapp .                         # open the current folder
runapp path/to/App.xcodeproj     # or a specific project / workspace
```

`runapp` opens `/Applications/RunApp.app`, falling back to `~/Applications` or the newest build in DerivedData.
Set `RUNAPP_APP=/path/to/RunApp.app` to override this.

## Build from source

```bash
brew install mise sweetpad-dev/tap/sweetpad swiftformat swiftlint xcbeautify
mise trust && mise install                          # Tuist, pinned in mise.toml
Scripts/generate                                    # Tuist → RunApp.xcodeproj (generated, not committed)
sweetpad run --scheme RunApp --on mac               # build and launch
sweetpad test --scheme RunApp --on mac              # unit tests
# or, without SweetPad:
xcodebuild -project RunApp.xcodeproj -scheme RunApp -destination 'platform=macOS' build | xcbeautify
```

For contributor and agent guidelines, see [AGENTS.md](AGENTS.md). For SweetPad's JSON output, see [docs/sweetpad-cli.md](docs/sweetpad-cli.md).

## Releasing

Updates ship through [Sparkle 2](https://github.com/sparkle-project/Sparkle). `Scripts/release` signs a Developer ID build, notarizes the zip and dmg, and publishes `appcast.xml`.

Prerequisites: the Developer ID Application certificate for RockieStar Inc. (team `DH5UQL44AR`), an `asc auth` profile named `default`, and the Sparkle EdDSA key in the login keychain under the account `RunApp`.

Back up the Sparkle private key (store the output offline; the first `Scripts/release` downloads the tool into `.build/sparkle/`):

```bash
.build/sparkle/bin/generate_keys --account RunApp -x ~/RunApp-sparkle-private-key.txt
```

```bash
Scripts/release 0.1.0            # version, optional build number (defaults to 1)
Scripts/release 0.1.0 1 --dry-run   # sign and package only; skip notarization, GitHub, commit, and push
```

Artifacts land in `build/release/`. A full run creates the GitHub release `v<version>` (zip and dmg), then commits `Project.swift` and `appcast.xml` as `chore(release): v<version>` and pushes.
