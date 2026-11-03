# KeyGrid — Design

Date: 2026-10-28
Status: draft, awaiting owner approval

## Intent

KeyGrid is a small macOS menu-bar utility that replaces three apps the
owner currently runs from three different publishers:

- **Snap** — ⌘1…⌘9 switch to the Nth icon in the Dock.
- **Rectangle** — hotkeys that resize/move the focused window.
- **Lasso** — a hotkey shows a grid over the screen; drag-select cells
  with the mouse and the focused window snaps to that rectangle.

None of those apps is missing a feature. The reason to build KeyGrid is
**trust**: one app, one owner, source the owner can read, built and
signed locally, with the smallest possible permission footprint. Every
design decision below should be read through that lens.

## Goals

1. Dock switcher: ⌘1…⌘9 activate the 1st…9th application icon as
   **visually shown in the Dock, left to right**, Finder included (so ⌘1
   is always Finder). ⌘0 is the 10th. Running unpinned apps and "recent
   applications" count, in the positions the Dock shows them. Launches
   the app if it is not running.
2. Window actions on the focused window, via global hotkeys: full,
   halves, quarters, three-quarters, move to the other display.
3. Grid placement: hotkey shows a configurable N×M grid overlay on a
   display; drag to select a rectangle of cells; the focused window takes
   that frame.
4. All behaviour configured from one plain-text file the owner edits by
   hand. The app reloads it on save.
5. Later (phase 2): a preferences window that reads and writes that same
   file. Nothing in phase 1 may make phase 2 awkward (no second source of
   truth, no settings in UserDefaults).
6. Code small and plainly commented so a reader with no Swift background
   can audit what it does.

## Non-goals

- App Store distribution, notarization, auto-update, crash reporting.
- Windows/Linux.
- Rectangle's full catalogue of actions, drag-to-edge snapping, window
  cycling, Spaces management.
- Per-app overrides or profiles.
- Mouse-driven features beyond the grid overlay.

## Anti-goals (failure even if it "works")

- **Any network code.** No telemetry, no update check, no fetch of
  anything. `grep -ri "URLSession\|NSURLConnection\|Network" Sources/`
  should find nothing.
- **Third-party dependencies.** Zero SwiftPM packages, no vendored code.
- **Permissions beyond Accessibility.** No Input Monitoring, no Screen
  Recording, no Notifications, no Full Disk Access, no Automation.
- **Hidden state.** No settings anywhere but the config file. No cache
  files beyond what macOS writes itself.
- **Requiring Xcode or a paid developer account to build.** The
  command line (`make`) is the primary build. Xcode is optional for
  editing and debugging, and opens the SwiftPM package directly.

## Constraints

- macOS 14 (Sonoma) or newer. The owner's machine runs macOS 26.
- Toolchain: builds with Command Line Tools alone (Swift 6.3 at time of
  writing). The owner may install Xcode for editing and debugging; the
  package must open in it, but the build must never depend on it.
- Two displays are the normal setup. One or three+ must not crash but
  need not be optimised.
- Signing: no Apple Developer identity exists. Build signs ad-hoc by
  default. Because macOS keys Accessibility trust to the code signature,
  an ad-hoc build may need the permission re-granted after each rebuild.
  The build must accept an optional signing identity (e.g. a free
  self-signed "Code Signing" certificate made in Keychain Access) via a
  variable so the identity stays stable across builds. Document this in
  the README.
- Repository: https://github.com/snaumenko/keygrid, local checkout
  `~/p/keygrid`.

## Decisions (how it gets made)

These were the owner's where marked; the rest are the author's calls and
can be revisited.

### Language and frameworks

- **Swift**, AppKit for everything in phase 1. SwiftUI only for the
  phase-2 preferences window. *(author's call, owner has no Swift
  background and deferred the choice)*
- Hotkeys via **Carbon `RegisterEventHotKey`**. It still works on current
  macOS, consumes the keystroke so the frontmost app never sees it, and
  needs no permission at all. *(author's call; alternative is a
  CGEventTap, which also needs only Accessibility but is more code)*
- Window control via the **Accessibility API** (`AXUIElement`): focused
  app → focused window → set `kAXPositionAttribute` and
  `kAXSizeAttribute`. Remember AX coordinates are top-left origin while
  `NSScreen` is bottom-left; put the conversion in one tested function.
- Dock order read from the **Dock's own Accessibility tree** (owner's
  decision: visual order, not pinned-only). Find the Dock process
  (`com.apple.dock`), get its `AXList` child, take children whose
  subrole is `AXApplicationDockItem` in order; each exposes `AXURL` for
  the app bundle and `AXTitle`. Separators, folders, minimized windows
  and the Trash are not application items and are skipped. Read on every
  hotkey press (cheap; avoids watching). Activation through
  `NSWorkspace.shared.openApplication(at:configuration:)`, which both
  activates a running app and launches a stopped one. Consequence: the
  dock switcher needs Accessibility like everything else; without it the
  hotkeys do nothing and the icon shows the warning state. *(author's
  call on mechanism; the semantics are the owner's)*
- Grid overlay is a borderless, non-activating `NSWindow` at
  `.screenSaver` level covering one display, with a custom `NSView` that
  draws the dim, the grid lines, and the current selection.

### Packaging and build

- **SwiftPM package, no `.xcodeproj`.** A `Makefile` builds the
  executable, assembles `KeyGrid.app` (Info.plist, icon, binary),
  codesigns it, and can copy it to `/Applications`. Targets: `make`,
  `make install`, `make run`, `make test`, `make clean`. *(author's call:
  a pbxproj is unreadable noise in diffs, which hurts the audit goal)*
- Info.plist sets `LSUIElement = true` (no Dock icon, menu bar only),
  bundle id `com.keygrid.app`.
- Launch at login via `SMAppService.mainApp`, toggled from the menu.

### Menu bar

Status item with a small template icon. Menu:

- Accessibility: granted ✓ / **Grant…** (opens the system prompt or the
  Settings pane).
- Open config file (opens in the default editor).
- Reload config.
- Launch at login (checkmark toggle).
- A line showing the last config error, if any (disabled item).
- Quit.

The icon should change (e.g. a dot or slash) when Accessibility is
missing or the config failed to parse, so problems are visible without
opening the menu.

### Config file

Path: `~/.config/keygrid/config.json`. On first launch, if absent, the
app writes the defaults there so the owner has something to edit.

Format: JSON. Hotkeys are strings like `"ctrl+alt+left"`,
`"cmd+1"`, `"ctrl+alt+cmd+right"`. Modifiers accepted: `cmd`, `ctrl`,
`alt` (alias `opt`), `shift`. Keys: letters, digits, `left right up
down`, `return`, `space`, `tab`, `escape`, function keys `f1`…`f20`.

Default content (also the schema by example):

```json
{
  "version": 1,
  "dock": {
    "enabled": true,
    "modifiers": "cmd"
  },
  "window": {
    "full":                "ctrl+alt+return",
    "leftHalf":            "ctrl+alt+left",
    "rightHalf":           "ctrl+alt+right",
    "topHalf":             "ctrl+alt+up",
    "bottomHalf":          "ctrl+alt+down",
    "topLeftQuarter":      "ctrl+alt+u",
    "topRightQuarter":     "ctrl+alt+i",
    "bottomLeftQuarter":   "ctrl+alt+j",
    "bottomRightQuarter":  "ctrl+alt+k",
    "leftThreeQuarters":   "ctrl+alt+e",
    "rightThreeQuarters":  "ctrl+alt+t",
    "otherDisplay":        "ctrl+alt+cmd+right"
  },
  "grid": {
    "hotkey": "ctrl+alt+space",
    "columns": 16,
    "rows": 12
  }
}
```

Rules:

- `dock.modifiers` plus digits 1–9 then 0 form the ten dock hotkeys for
  Dock positions 1–10. Position 1 is always Finder because macOS pins it
  there. Setting `enabled` to false unregisters them (useful because
  ⌘1…⌘9 shadow tab shortcuts in browsers). *(⌘0 = 10th is the author's
  call)*
- Any `window` action may be set to `null` or omitted to leave it
  unbound.
- Reload on change: watch the file (and its directory, since editors
  save by replace) with a `DispatchSource` or `FSEvents`. On a parse
  error keep the last good config, show the error in the menu, flag the
  icon. Never crash on bad config.
- Unknown keys are ignored (forward compatibility for phase 2).

### Window action semantics

All actions use the **visible frame** of the display the window is on
(excludes menu bar and Dock).

| Action | Frame |
|---|---|
| full | whole visible frame |
| leftHalf / rightHalf | 50% width, full height |
| topHalf / bottomHalf | full width, 50% height |
| four quarters | 50% × 50% |
| leftThreeQuarters / rightThreeQuarters | 75% width, full height |
| otherDisplay | move to the next display (wrapping), keeping the window's size and position as *fractions* of the source visible frame, then clamp to fit |

"Full" means filling the display, **not** macOS native full-screen
Spaces. If a window refuses the exact size (minimum sizes, fixed
aspect), set what it accepts and do not retry.

The frame arithmetic must live in pure functions
(`(visibleFrame, action) -> targetFrame`) with unit tests, separate from
the AX code that applies them.

### Grid semantics

1. Hotkey pressed. Capture the currently focused window *now*, before the
   overlay appears.
2. Overlay covers the display **under the mouse cursor** *(author's
   call; the alternative is the focused window's display)*. Dim the
   display, draw `columns × rows` cells over the visible frame.
3. Mouse down on a cell anchors the selection. Drag extends it to the
   rectangle spanned by the anchor cell and the cell under the cursor.
   A plain click with no drag selects one cell.
4. Mouse up applies the selected rectangle to the captured window and
   hides the overlay.
5. Escape, or the hotkey again, cancels. Clicking outside the overlay is
   impossible because it covers the display; losing focus to another
   app also cancels.
6. The overlay must not steal activation from the target app in a way
   that changes which window is "focused" — hence capture in step 1 and
   a non-activating panel.

Selection math (`cell indices -> frame`) is a pure, tested function.

### Accessibility onboarding

On launch call `AXIsProcessTrustedWithOptions` with the prompt option.
Until trusted, hotkeys register but every action does nothing except
flag the icon (the dock switcher reads the Dock's AX tree, so it needs
the permission too).

### Settled by the builder check (author's calls)

- A window's display is the `NSScreen` with the largest intersection
  with its frame.
- `otherDisplay` steps through `NSScreen.screens` by index, wrapping.
- Grid overlay is an `NSPanel` with `.nonactivatingPanel`, made key so
  it receives Escape; it cancels on `didActivateApplication` for any pid
  other than the captured window's.
- `RegisterEventHotKey` failures (e.g. Rectangle still running and
  owning the same combo) are reported on the menu's error line, not
  silently dropped.
- Swift 5 language mode under the Swift 6 toolchain, to keep the AX and
  Carbon interop readable.
- First task of the plan is a spike confirming Carbon hotkeys and the
  Dock AX tree work on macOS 26.

## Phase 2 (designed now, built later)

A SwiftUI preferences window opened from the menu. Hotkey recorder
fields for every binding, steppers for grid size, a dock enable toggle.
It loads the config file, edits an in-memory copy, and **writes the file
back**; the running app then picks the change up through the same
file-watch path as a hand edit. The config model type must therefore be
`Codable` both ways and preserve unknown keys or at least not destroy
them. No settings outside the file.

## Testing

- Unit tests (`swift test`): hotkey string parsing, config decoding with
  defaults and bad input, window-action frame math, grid selection math,
  AX↔NSScreen coordinate conversion, dock plist parsing from a fixture.
- Manual checklist in the README: grant Accessibility, each hotkey on
  each display, grid on each display, config edit reloads, bad config
  shows an error and keeps working, quit and relaunch.

## Left to the builder

- Source file layout and naming.
- Menu-bar icon artwork (a template PDF/SVG is fine; keep it tiny).
- Exact dim colour, grid line style, selection highlight.
- How the Makefile locates an optional signing identity (env var is
  fine).
- Whether to debounce config reloads.
- README contents beyond the signing note and manual checklist.

## Open questions resolved during brainstorm

- Name: KeyGrid, chosen on 2026-11-02 in place of the working title the
  project started under; domain availability was not checked. Repo:
  github.com/snaumenko/keygrid.
- No paid Apple Developer membership now or for this phase.
