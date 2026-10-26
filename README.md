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
brew install xcodegen sweetpad-dev/tap/sweetpad swiftformat swiftlint xcbeautify
xcodegen generate                                   # RunApp.xcodeproj is generated, not committed
sweetpad run --scheme RunApp --on mac               # build and launch
sweetpad test --scheme RunApp --on mac              # unit tests
# or, without SweetPad:
xcodebuild -project RunApp.xcodeproj -scheme RunApp -destination 'platform=macOS' build | xcbeautify
```

For contributor and agent guidelines, see [AGENTS.md](AGENTS.md). For SweetPad's JSON output, see [docs/sweetpad-cli.md](docs/sweetpad-cli.md).
