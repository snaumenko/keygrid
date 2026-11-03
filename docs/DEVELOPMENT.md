# Development

How to set up a machine and build KeyGrid from source.

## Requirements

- macOS 14 or newer. The app targets 14; development happens on 26.
- Apple Command Line Tools with Swift 6. Check with `swift --version`.
  Install or update with:

  ```bash
  xcode-select --install
  ```

- Xcode is optional. It opens `Package.swift` directly for editing and
  debugging. The command-line build never needs it.
- No Apple Developer account. Builds are signed ad hoc.
- `gh` (GitHub CLI) for issues and pull requests.

## Build and run

```bash
git clone https://github.com/snaumenko/keygrid ~/p/keygrid
cd ~/p/keygrid
make test      # unit tests
make run       # build, assemble dist/KeyGrid.app, open it
make install   # copy the bundle to /Applications
make clean     # remove .build and dist
```

`make` alone builds the release binary. `CONFIG=debug make run` builds
debug.

The app is menu-bar only: look for the grid icon at the top right, not in
the Dock.

## Tests

Tests live in `Tests/` and use **Swift Testing** (`import Testing`,
`@Test`, `#expect`). XCTest is not used: it ships only with Xcode, and the
build must work with the Command Line Tools alone.

Always run tests through `make test`. On a machine without Xcode, SwiftPM
does not find the Testing framework by itself, and the Makefile passes the
search path and rpaths it needs. Plain `swift test` fails there. On a
machine with Xcode selected, the Makefile detects that and passes nothing.

## Accessibility permission

The app moves other apps' windows and reads the Dock, so macOS asks for
Accessibility on first launch. Grant it in System Settings → Privacy &
Security → Accessibility.

macOS ties that grant to the app's code signature. An ad-hoc signature
changes on every build, so after `make install` macOS may ask again. To
keep one grant across rebuilds, sign with a stable identity:

1. Keychain Access → Certificate Assistant → Create a Certificate.
   Any name, type Code Signing; below it is `<certificate name>`.
2. Build with it:

   ```bash
   SIGN_IDENTITY="<certificate name>" make install
   ```

## Repository layout

```
Package.swift            SwiftPM manifest, two targets
Makefile                 build, test, bundle, run, install, clean
Resources/Info.plist     bundle id, menu-bar-only flag, version
Sources/KeyGridCore/     pure logic, no AppKit, unit-tested
Sources/KeyGrid/         the app: menu bar, hotkeys, Accessibility, Dock, overlay
Tests/KeyGridCoreTests/  unit tests, Swift Testing
docs/DESIGN.md           the design the app was built from
docs/ARCHITECTURE.md     how the pieces fit together
.github/workflows/ci.yml make test and make bundle on every PR
.github/ISSUE_TEMPLATE/  bug report and feature idea forms
SECURITY.md              how to report a security problem privately
```

## Workflow

Issues, branches, and PRs follow the Dev workflow section in `AGENTS.md`.
In short: pick an issue, branch `<issue-number>-<slug>`, write the task
doc in `docs/work/`, implement, open a PR that closes the issue.

CI runs `make test` and `make bundle` on a GitHub macOS runner for every
pull request and uploads `KeyGrid.app` as an artifact.

## Known setup problem

If every `swift build` fails while compiling `Package.swift` with linker
errors about `PackageDescription`, the Command Line Tools install has
stale files from an older Swift next to the current ones. Fix:

```bash
sudo rm /Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface
```

Or reinstall the Command Line Tools.
