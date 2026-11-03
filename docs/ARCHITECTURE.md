# Architecture

How the pieces of KeyGrid fit together. Type-level comments in the
source describe one type at a time; this file tells the stories that span
several types. It grows with each task.

## Two targets

- `Sources/KeyGridCore/`: pure logic with a right answer that needs no
  screen. Parsing, the config model, frame math. Imports no framework at
  all, so nothing in it can touch windows, files, or permissions. Every
  type here must have unit tests.
- `Sources/KeyGrid/`: the app. Menu bar, global hotkeys, Accessibility,
  the Dock, the grid overlay. Everything that talks to macOS.

The split exists so an auditor has a clean line: anything under
`KeyGridCore` is inert by construction, because it imports nothing that
can reach the operating system. It also keeps the tested logic in a
library, which is the shape SwiftPM tests most simply.

## How a setting travels

1. The user edits `~/.config/keygrid/config.json` (or
   `$XDG_CONFIG_HOME/keygrid/config.json`). It is the only place the
   program keeps settings. On first launch `ConfigStore` writes
   `Config.defaultJSON` there; it never overwrites an existing file.
2. `ConfigStore` (`Sources/KeyGrid/ConfigStore.swift`) reads the bytes
   and decodes them with Foundation's `JSONDecoder` into a `ConfigFile`
   (`Sources/KeyGridCore/Config.swift`). `ConfigFile` is a plain copy of
   the JSON: one optional field per key, no defaults, no checks. It lives
   in Core because `Codable` is in the Swift standard library; the decoder
   that needs Foundation stays in the app. Unknown keys are ignored, a
   misspelled window action name among them.
3. `Config(validating:)` turns the `ConfigFile` into a `Config`. The file
   is the whole truth: a section it does not have is off (no `dock`
   section, no Dock shortcuts; no `window` section, no window bindings;
   no `grid` section, no grid). Inside a present `dock` section a missing
   field takes its default; inside a present `window` section a missing
   or `null` action is unbound; inside a present `grid` section a missing
   `size` takes its default (6) while a missing or `null` `hotkey`
   leaves the grid without a shortcut. The grid's `size` must be one of
   6, 12, 18, 24, 30, 36, and the `columns` and `rows` fields of version
   0.3.0 are refused by name so the file gets edited rather than silently
   falling back to the default. Hotkey text such as
   `"ctrl+alt+left"` and modifier text such as `"ctrl+alt"` are parsed,
   and the rules are checked (every shortcut
   has at least one modifier; no two shortcuts the same, across
   sections). A broken value produces a `ConfigError` that names the JSON
   field, for example `dock.modifiers: "1" is not a modifier`,
   `grid.size: 7 is not one of 6, 12, 18, 24, 30, 36`,
   `grid.columns was replaced by grid.size; remove grid.columns`,
   `window.topHalf was replaced by window.sweepUp and window.sweepDown;
   remove window.topHalf`, or
   `ctrl+alt+1 is bound twice: dock.2, window.full`.
4. If decoding or validation fails, `ConfigStore` keeps the previous
   `Config` in `current` and puts a one-line message in `lastError`. If it
   succeeds and the result differs from `current`, it stores it and calls
   `onChange`. After every load it calls `onStatus` with `lastError`, nil
   when clear, so a listener learns when the user fixed the file.
5. `AppController.applyConfig` answers `onChange`: it unregisters every
   shortcut in `HotkeyCenter`, then registers each entry of
   `Config.dockHotkeys`, binding position N to
   `DockSwitcher.activate(position: N)` (see "How a Dock shortcut
   works"). Registration failures (for example another app owns the key)
   are logged and collected into `AppController.hotkeyFailures`; the
   shortcuts that did register stay registered. `lastError` and
   `hotkeyFailures` reach the menu's error line through `StatusState`
   (see "How the status menu works").
6. `ConfigStore` watches both the config directory and the file with
   `DispatchSource`s. The directory watch catches editors that save by
   writing a new file and renaming it over the old one; the file watch
   catches editors that write in place, and is reopened after every load
   so it follows a replaced file. A burst of events is debounced for
   200 ms, then the store reloads from step 2.

`Config` is the only type the rest of the program reads settings from.
`ConfigFile` is seen only by the decoder and the validation step. The
config grows by section: V1 has `dock`; V2 adds `window`; V3 adds
`grid`. Each section adds its hotkeys to `allHotkeys` under its own
labels (`dock.3`, `window.leftHalf`, `grid.hotkey`), and the
duplicate check in step 3 is where two sections binding the same key is
caught. The `version` field is written and not checked; a check and
migrations come with the decision to freeze the file format. Until then
an old file is deleted or edited by hand.

## How a hotkey travels

1. The user writes a shortcut as text in `~/.config/keygrid/config.json`.
   It is either a full shortcut such as `"ctrl+alt+left"` (the window and
   grid sections) or a modifier-only string such as
   `"ctrl+alt"` in `dock.modifiers`, which the program combines with the
   backtick and the digits 1…9 and 0 to make the eleven Dock shortcuts.
   The built-in
   defaults hold ⌃⌥ (⌃⌥\` and ⌃⌥1 for the Dock, ⌃⌥⏎ and ⌃⌥[ for a placement,
   ⌃⌥← for a move, ⌃⌥⇧← for a sweep, ⌃⌥. for the next display,
   ⌃⌥Space for the grid): few app
   menus use ⌃⌥, while
   ⌘ with a digit switches tabs
   in most browsers, ⌥ with a key types an accented or symbol character
   on most layouts, and ⌃ with a letter edits text in terminals and in
   every macOS text field. Since a global hotkey takes the key away from
   the app in front, a default in any other family would silently break
   those apps; ⌘1 did until the Dock default moved to ⌃⌥ in version 0.4.
2. `Hotkey.parse(_:)` (in `KeyGridCore/Hotkey.swift`) turns a full
   shortcut into a `Hotkey`: a `Modifiers` set plus a virtual key code
   looked up in `KeyNames`. `Config.parseModifiers` reads the modifier-only
   form. Bad text produces a `HotkeyParseError` or `ConfigError` saying
   what was wrong: blank text, no key, two keys, or an unrecognised word,
   which the error carries.
3. `HotkeyCenter` (`Sources/KeyGrid/HotkeyCenter.swift`) registers the
   `Hotkey` with macOS through Carbon's `RegisterEventHotKey`, passing
   `hotkey.modifiers.carbonFlags` and `hotkey.keyCode` unchanged, and runs
   the bound closure on the main thread when the key is pressed. Carbon
   hotkeys need no permission, and macOS consumes the keystroke before
   normal key delivery, so the app in front does not receive it. Apps that
   watch the keyboard through a `CGEventTap`, as some window-management
   and Dock utilities do, still see the key and may act on it too; two
   apps bound to one shortcut both act, which is why the README asks for
   such utilities to be quit or re-keyed.
4. When the user presses the keys, macOS calls back into the app, which
   runs the closure bound to that hotkey. For a Dock shortcut that is
   `DockSwitcher.activate(position:)`, described in "How a Dock shortcut
   works"; for a window shortcut, `WindowMover.perform(_:)`, described in
   "How a window action works"; for the grid shortcut,
   `AppController.toggleGrid`, described in "How the grid overlay works".
5. A shortcut that could not be registered is named in the menu's error
   line by its config label and the hotkey in its canonical text form,
   `hotkey.description`, which always spells one shortcut the same way
   (see "How the status menu works").

## How a Dock shortcut works

1. `Config.dockHotkeys` (`Sources/KeyGridCore/Config.swift`) pairs each
   position 1…11 with a `Hotkey`: `dock.modifiers` plus the backtick for
   position 1, the digits 1…9 for positions 2…10, and 0 for position 11.
   The keys sit `` ` `` 1…9 0 left to right on the top row, so the Nth
   key gets the Nth icon; and since macOS pins Finder first, the digit N
   is the Nth icon after Finder, which is how a person counts their
   Dock. The key is a position (`kVK_ANSI_Grave`, `0x32`), not a
   character: with another layout active on a US (ANSI) keyboard it is
   still the key left of 1. On an ISO keyboard, the European shape, that
   code is the key between left Shift and Z, and the key left of 1
   reports `kVK_ISO_Section` (`0x0A`), which `KeyNames` does not list;
   the README says which key is Finder there. The list is empty when
   `dock.enabled` is false.
2. `AppController.applyConfig` registers each pair with `HotkeyCenter`
   and binds it to `DockSwitcher.activate(position:)`.
3. On a press, `DockSwitcher` (`Sources/KeyGrid/DockSwitcher.swift`)
   reads the Dock's accessibility tree: the Dock is an ordinary app
   (`com.apple.dock`), its icons are the children of an `AXList`, and
   application icons have the subrole `AXApplicationDockItem`.
   Separators, folders, minimized windows and the Trash have other
   subroles and are skipped. Position N is the Nth application icon left
   to right, Finder first because macOS pins it there; running apps that
   are not pinned, and "recent applications", count where the Dock shows
   them. The tree is read on every press, not cached, so the numbering
   follows the Dock as apps open and quit.
4. `DockSwitcher` performs the icon's `AXPress` action, which the Dock
   treats like a plain click: a running app comes forward, a stopped one
   launches. If the press fails it opens the item's bundle URL with
   `NSWorkspace` instead. A position past the last icon only logs.
   Before the press, `DockSwitcher` reads the bundle identifier of the
   icon's bundle (`Bundle(url:)`, one `Info.plist` read) and asks
   `NSRunningApplication.runningApplications(withBundleIdentifier:)`
   whether that app runs, which is how the Dock decides between
   activating and launching; `activate` returns the running app it asked
   forward, or nil when nothing was activated or the app was stopped and
   is now launching.
5. When `Config.dockHighlight` is on (the `dock.highlight` key, on
   unless the file says `false`) and `activate` returned an app,
   `AppController.highlightFocusedWindow(of:label:)` draws a border
   around that app's focused window. The Dock's press is answered by the
   app on its own time, so the app is active some milliseconds after the
   call returns: `AppController` reads the window at once when the app is
   already in front (the shortcut named the active app, whose windows the
   Dock brings forward without an activation), and otherwise asks the
   app every 50 milliseconds whether it is active, through
   Accessibility (`kAXFrontmostAttribute` on its application element),
   giving up after 1.5 seconds with a `no border;` line in the log. The
   app's own answer is used rather than
   `NSWorkspace.didActivateApplicationNotification`, which on a first
   press for a background app did not reach KeyGrid in time. Once the
   app is active, `WindowMover.focusedWindowFrame(of:)`
   (`Sources/KeyGrid/WindowMover.swift`) reads the focused window of
   that app, named rather than taken from the front because
   `frontmostApplication` can still name the previous app at that
   moment, and converts its frame to AppKit coordinates (see "Coordinate
   systems"). `WindowHighlight.show(around:)`
   (`Sources/KeyGrid/WindowHighlight.swift`) lays a borderless,
   non-activating panel that ignores the mouse over that frame at
   `.screenSaver` level, the grid overlay's level, strokes a 3-point
   rounded border in the system accent colour along the window's edge,
   holds a quarter of a second, fades over four tenths of a second with
   `NSAnimationContext`, and removes the panel. A new Dock press replaces
   a border still showing; a config reload ends a pending wait. An app
   with no focused window at the first read is read once more 0.3
   seconds later, because the press can still be making the window: a
   click on the active app with no windows opens one, a click on an app
   with every window minimized brings one back. No focused window on
   the second read, a window that did not give its frame, or a lost
   Accessibility permission is logged as `dock.N: no border; <reason>`
   and nothing is drawn. A
   stopped app gets no border: its first window appears seconds later
   with the app's own launch animation, which already shows where it is.
6. Reading the tree needs the Accessibility permission (`Accessibility`,
   `Sources/KeyGrid/Accessibility.swift`). Without it the read fails
   with a logged "permission is not granted" and the shortcut does
   nothing. `AppController` asks for the permission once at launch, then
   re-checks every two seconds because macOS posts no documented change
   notification, and `StatusMenu` shows the icon with a badge in its
   corner while it is missing. The grant is tied to the code signature, so an ad-hoc build
   may need it again after a rebuild; `SIGN_IDENTITY` in the Makefile
   keeps the signature stable.

## How a window action works

1. `Config.windowBindings` (`Sources/KeyGridCore/Config.swift`) maps
   each bound `WindowAction` to a `Hotkey`, read from the `window`
   section of the config file. An action that is `null` or absent there
   has no shortcut.
2. `AppController.applyConfig` registers each pair with `HotkeyCenter`
   and binds it to `WindowMover.perform(_:)`.
3. On a press, `WindowMover` (`Sources/KeyGrid/WindowMover.swift`) asks
   `NSWorkspace` for the app in front, takes that app's Accessibility
   element, and reads its focused window's position and size. Those come
   in Accessibility coordinates; `AXCoordinates.fromAX` turns them into an
   AppKit `Rect` (see the section "Coordinate systems" in this file).
4. The window's display is the `NSScreen` whose frame overlaps the window
   most. A window that overlaps no display (possible for a moment after a
   display is unplugged) is logged and treated as being on the first
   display. For the placements that depend on the display alone
   (`full`, `leftHalf`, `rightHalf`, `centerTwoThirds`),
   `Geometry.frame(for:in:)` computes the new frame from that display's
   `visibleFrame`; `centerTwoThirds` insets it by one sixth of its
   shorter edge on every side, equal gaps being the point. For `center`,
   `Geometry.centered` keeps the window's size and moves its center onto
   the visible frame's. `full` is a toggle: when the window does not fill
   the visible frame, `WindowMover` stores its frame in `previousFrames`
   (`FrameMemory` in `Sources/KeyGridCore/FrameMemory.swift`, keyed by
   the window's Accessibility element, newest 32, in memory only) and
   fills; when the window already fills the visible frame
   (`Geometry.sameFrame` against the full frame), the stored frame is
   taken back out and placed as it was, or, with none stored, the press
   is logged as `window.full ignored: the window already fills its
   display and no earlier frame is remembered` and nothing is written. The memory holds the frame the window actually took after
   the fill as well (`FilledWindow`), and a window still at that frame
   counts as full, so a window that keeps a few points short of full,
   as Terminal does, still toggles back. When the action is a half and the window already
   has the half's frame (`Geometry.sameFrame`, every edge within a
   point), `WindowMover` instead finds the display on that side the way
   a move at the edge does (`Geometry.adjacentDisplay`, described with
   the moves in this step) and places the window as that display's
   opposite half, `Geometry.frame(for:in:)` on the destination's
   `visibleFrame`, so it is a true half there whatever that display's
   grid. For a sweep, `WindowMover` first gets the display's
   grid from `Geometry.gridLayout(for:size:)` with the config's
   `grid.size` (the same grid the overlay draws there), then
   `Geometry.sweep` (`Sources/KeyGridCore/EdgeGeometry.swift`) moves
   one edge of the window's current frame: the edge facing the arrow
   steps to the next grid line in that direction, or, when that edge is
   already at the display's edge, the opposite edge steps the same way,
   never below one cell. A sweep that returns the frame unchanged is
   logged as `can go no further` and nothing is written. For a move,
   `Geometry.move` shifts the whole window to the next grid line in the
   arrow's direction, size unchanged, or returns nil when the facing
   edge is already at the display's edge or hanging past it. Then
   `WindowMover` asks
   `Geometry.adjacentDisplay` for the display beyond that edge, over the
   whole display frames `NSScreen.screens` reports (edge to edge, as
   macOS lays them out); one qualifies when it shares the edge and
   overlaps the window's span along it, corner contact excluded. With
   one found, `Geometry.carry` lands the window against the destination's
   near edge, the same size in grid cells on the destination's own grid
   (from `gridLayout` for that display), keeping its row or column index
   across the other axis; with none, the move is logged as `can go no
   further` and nothing is written. For `previousDisplay` and
   `nextDisplay`, `Geometry.displayOrder` sorts the display frames left
   to right (ties bottom to top), the window's display's neighbour in
   that order is the target, wrapping at both ends, and
   `Geometry.frameMoving` reapplies the window's position and size as
   fractions of the source visible frame onto the destination's, clamped
   to fit; with one display the press logs `only one display is
   attached` and nothing is written.
5. `AXCoordinates.toAX` converts the new frame back, and `WindowMover`
   writes it as size, then position, then size again: position first can
   be refused when the current size does not fit the destination, size
   first can be clamped by the display the window is still on. A window
   with a minimum size or fixed aspect keeps what it accepts; there is no
   retry. `WindowMover` then reads the frame back; a frame that differs
   from the target by more than a point is logged at notice level, so
   "nothing happened" has a record in `log show`.
6. Every failure (no app in front, no focused window, Accessibility
   missing, a sweep, move, or repeated half that can go no further, a
   display jump with one display) is
   logged with the action's
   label, for example `window.leftHalf ignored: Accessibility permission
   is not granted`, and the window is left alone. A failed press is
   only logged; the menu's error line is for the config file and shortcut
   registration.

## How the grid overlay works

1. `Config.grid` (`Sources/KeyGridCore/Config.swift`) holds the grid's
   `hotkey` and `size`, the cell count along the shorter edge of a
   display. `AppController.applyConfig` registers the hotkey with
   `HotkeyCenter` bound to `AppController.toggleGrid`, and hands the size
   to `GridOverlay`. A reload cancels any grid that is showing first,
   because its size or its hotkey may have changed.
2. On a press while the grid is showing, `toggleGrid` cancels it. On any
   other press it first captures the focused window with
   `WindowMover.capture()`: the app in front, its process id, and the
   Accessibility element of its focused window, kept in a
   `CapturedWindow`. Capturing before anything appears on screen is what
   makes the result independent of focus changes while the grid is open.
   A failed capture (no app in front, no focused window, no Accessibility
   permission) logs `grid.hotkey ignored: <reason>` and shows nothing.
3. The grid goes on the display under the mouse, the `NSScreen` whose
   `frame` contains `NSEvent.mouseLocation`, which may be a different
   display from the window's. `GridOverlay.show`
   (`Sources/KeyGrid/GridOverlay.swift`) opens a borderless,
   non-activating `NSPanel` the size of that display at `.screenSaver`
   level, so it covers full-screen apps and the menu bar, and joins every
   Space. The panel is made the key window so it receives Escape;
   `.nonactivatingPanel` means becoming key does not activate KeyGrid,
   so the captured app stays in front.
4. `GridOverlay.show` turns `size` into a column and row count for this
   display with `Geometry.gridLayout(for:size:)`
   (`Sources/KeyGridCore/GridGeometry.swift`): `size` cells along the
   shorter edge of the visible frame, and along the longer edge `size`
   scaled by the display's shape, rounded to the nearest multiple of 6
   and never below 6, so cells stay roughly square and halves and thirds
   fall on cell edges both ways. A landscape display puts `size` on the
   rows (16:9 gives 12×6); a portrait display puts it on the columns
   (6×12); each display gets its own layout at show time. The panel's
   `GridView` dims the whole display and draws those cells over the
   display's `visibleFrame`, the same frame the window actions use, so a
   half dragged on the grid is the frame `leftHalf` places, to the point,
   and a sweep or a move steps along the lines the grid draws.
   Which cell the mouse is in, and which frame two cells
   span, come from `Geometry.gridCell` and `Geometry.gridFrame`
   (`Sources/KeyGridCore/GridGeometry.swift`), which also put row 0 at
   the top; the view converts points between screen and view coordinates
   by the display's origin and does no cell arithmetic. Before the mouse
   goes down the cell under it is highlighted. Mouse down anchors;
   dragging extends the selection to the rectangle spanned by the anchor
   and the cell under the mouse; a click without a drag selects one
   cell.
5. Mouse up hides the panel, converts the selection back to screen
   coordinates, and calls `WindowMover.place(_:at:label:)` with the
   `CapturedWindow` and the label `grid`. `place` writes the frame and
   reads it back exactly as a window action does (step 5 of "How a
   window action works"), so a window that kept a different frame is
   logged the same way.
6. Cancelling hides the panel and leaves the window alone. Escape reaches
   `GridView.keyDown` because the panel is key; a second press of the
   grid hotkey reaches `toggleGrid`, which sees `isShowing`; a
   `didActivateApplication` notification for any process other than the
   captured window's means the user switched apps; a
   `didChangeScreenParameters` notification means the display the grid
   was drawn against may have moved. `GridOverlay` reports each of the
   last three to `AppController` with a sentence saying which, and
   `AppController` logs every cancel at notice level with that cause.

## How the status menu works

1. `AppController` keeps three inputs: whether the Accessibility
   permission is granted (checked at launch and every two seconds), the
   config file's last error from `ConfigStore.onStatus` (nil when it
   loaded), and the shortcuts `applyConfig` could not register, one
   line each.
2. Whenever one changes, `AppController.refreshMenu` asks
   `StatusState.resolve` (`Sources/KeyGridCore/StatusState.swift`)
   for the state: `needsAccessibility` if the permission is missing,
   else `problem` with the config error (or, with none, the failed
   shortcuts), else `ok`; and `StatusState.errorLine` for one line of
   text, the first line of the problem prefixed `Config error: ` or
   `Shortcut failed: ` and followed by `(+N more)` if there are more
   (a config error is one line, so that is mostly the failed shortcuts),
   cut to `StatusState.maxShown` characters because a menu item does not
   wrap. `refreshMenu` drops the config file's path from the front of a
   load error first: the log needs it, the menu (one file) does not. A
   directory that cannot be watched stays an error after later good
   loads, since edits are still not seen until restart.
3. `StatusMenu.update` draws it: the badged icon for
   `needsAccessibility`, the problem icon (a filled disc with an exclamation mark cut out of it,
   in the badge's corner) for a problem, the plain icon for `ok`;
   the first menu
   item says
   `Accessibility: granted` or offers `Grant Accessibility…`; the error
   line is a disabled menu item, shown in every state that has one, so a
   broken file is still visible while the permission is missing. The
   menu decides nothing; the pure function does, and has the tests.
4. The menu's other items are plain actions `AppController` fills in:
   open the config file in the app macOS uses for `.json`, reload it,
   quit, **Launch at Login** (see "How launch at login works"), and
   **About KeyGrid**, which opens `AboutWindow`
   (`Sources/KeyGrid/AboutWindow.swift`). About is one window, made on
   the first open and brought forward after, its labels rebuilt each
   time. Its words are `About` (`Sources/KeyGridCore/About.swift`):
   the README's first sentence and its "What this app never does" list,
   typed once more there and checked against `README.md` by a test, so
   the README stays the master copy. The version is
   `CFBundleShortVersionString` and `CFBundleVersion` from
   `Resources/Info.plist`, formatted by `About.versionText`; the
   copyright line is `NSHumanReadableCopyright` from `Info.plist` too; the
   config path is `ConfigStore.file`; the Accessibility state is the
   value `AppController` keeps for the icon. The signature line asks the
   Security framework for the running bundle's signing certificate
   (`AboutWindow.signingIdentity`) and `About.signatureText` words it:
   "Signed by <certificate name>", or the ad-hoc line that explains why the
   Accessibility grant disappears on every rebuild. The repository link
   is an attributed string AppKit opens in the browser on click; the app
   fetches nothing. Because KeyGrid is menu-bar only (`LSUIElement`),
   `show` activates the app so the window comes forward, and closing it
   activates the app the user was last in: the one in front when About
   opened, or any other app activated while it stayed open.

## How launch at login works

1. The login item is macOS's record, not a KeyGrid setting: it lives
   in the system's Login Items list, which System Settings → General →
   Login Items & Extensions shows, the way the Accessibility grant lives
   in the system's privacy database. `config.json` holds the app's
   settings and says nothing about login; a person can turn the item on
   or off in System Settings without KeyGrid, and KeyGrid shows
   whatever the system says.
2. `StatusMenu` is its menu's `NSMenuDelegate`; just before the menu
   drops down it calls `onMenuWillOpen`, and `AppController.refreshMenu`
   runs. `refreshMenu` asks `SMAppService.mainApp.status`
   (ServiceManagement, Apple's API for an app registering itself as a
   login item, macOS 13 and later) and maps the answer onto
   `LoginItemState` (`Sources/KeyGridCore/LoginItem.swift`):
   `notRegistered` → `off`, `enabled` → `on`, `requiresApproval` →
   `needsApproval` (registered, but macOS wants the person to allow it in
   System Settings), `notFound` → `off` (macOS reports `notFound` for an app
   that has never registered, so it cannot mean "disabled"), any status
   this macOS adds later → `unavailable`. `LoginItemState` gives the item its title,
   checkmark and enabled flag, in one tested place; `StatusMenu.update`
   draws them. Reading the status on every open is what keeps the
   checkmark honest after a change made in System Settings.
3. A click runs `AppController.toggleLaunchAtLogin`: `off` →
   `register()`, `on` → `unregister()`, `needsApproval` →
   `SMAppService.openSystemSettingsLoginItems()`, the pane where the
   allowing happens; `unavailable` is disabled. After a `register` that
   leaves the status at `requiresApproval`, the pane is opened at once,
   since the person just asked for the item and macOS is waiting for one
   more click. Errors are logged under the `login` category and the menu
   then shows whatever macOS reports.
4. The login item points at the bundle that was running when it was
   registered. From `/Applications/KeyGrid.app` (`make install`) that
   or `~/Applications/KeyGrid.app` it is stable. From
   `dist/KeyGrid.app` (`make run`) it is the build folder, which the
   next build deletes and recreates, so a notice is logged naming the
   path and `make install`; registering is still
   allowed, because a person checking the feature from `dist/` would
   otherwise be refused for no visible reason.

## Coordinate systems

macOS describes the same screen in two coordinate systems, and a window
frame crosses between them once in each direction.

- **AppKit**: origin at the bottom-left corner of the primary display, y
  grows upward. `NSScreen.frame`, `NSScreen.visibleFrame`, and every
  `Rect` that `Geometry` reads or returns use it.
- **Accessibility API**: origin at the top-left corner of the primary
  display, y grows downward. `kAXPositionAttribute` on a window uses it,
  as do the Core Graphics display functions.

Both share x, width, height, and the unit (points). Only y flips, around
the primary display's *full* frame height: the top edge of an AppKit
frame, `maxY`, becomes the Accessibility position `primaryHeight - maxY`.
The primary display is the one AppKit lists first in `NSScreen.screens`
(not `NSScreen.main`, which is the display with keyboard focus). Its
full height is the pivot because the menu bar and Dock shrink the visible
frame but move neither origin.

`AXCoordinates.toAX(_:primaryHeight:)` and
`AXCoordinates.fromAX(_:primaryHeight:)` in Core are that arithmetic; the
pivot is a parameter because Core imports no framework. `WindowMover` in
the app is the only intended caller: it converts a frame once when
reading it from the Accessibility API and once when writing it back,
for a window action and for a grid placement alike, and once more in
`focusedWindowFrame(of:)`, the read that gives the Dock highlight its
frame. A `Rect` holds Accessibility coordinates only on those lines;
everything in between is AppKit.

## The icon

KeyGrid's icon is a rounded square border with nine dots inside, a
3×3 grid. It is committed as finished files in `Resources/`, and the
Makefile copies them into the bundle: `KeyGrid.icns` is the app icon
(`CFBundleIconFile` in `Info.plist` names it), and `MenuBarIcon.png`,
`MenuBarIconBadge.png` and `MenuBarIconProblem.png` (with `@2x`
partners for Retina) are the menu bar images, black on transparent,
which `StatusMenu` loads as template images so macOS tints them to the
menu bar. The badge version is shown while the Accessibility permission
is missing, the problem version (a filled disc with an exclamation mark cut out of it, in
the same corner) while the config file or some shortcuts have a problem.
The files were rendered once from `Resources/KeyGridIcon.svg`, which is
the editable source and is not used at build or run time. The drawing,
in an 18-unit square with the origin at the top-left: the board is a
rounded rectangle stroked 1.5 wide along the very edge (inset 0.75,
corner radius 3.5); the nine dots are filled circles of radius 1.5
centred on (5, 9, 13) × (5, 9, 13); the badge is a filled circle of
radius 3 at (14.5, 14.5), punched out of the board first with a clear
ring of radius 4.3 so it separates from the border, twice a dot's size
and breaking the border so it does not read as a tenth dot at 18
points; the problem mark is the badge with an exclamation mark cut out
of it. The menu bar images are black on transparent; the app icon is one
dark slate (`#2B3340`) on transparent, edge to edge with no margin,
which Finder does not retint. A keycap with a letter was tried first and
dropped: at 18 points a letter in perspective reads as a smear, while
the nine-dot grid says what the app does and stays crisp at every size.

To render the files again, export the SVG at 18 and 36 px in black for
`MenuBarIcon.png` and `MenuBarIcon@2x.png`, with the badge for the
`Badge` pair and with the exclamation mark for the `Problem` pair (the
SVG's closing comment holds the pieces to swap in), and at 16, 32, 64,
128, 256, 512 and 1024 px in `#2B3340` as `icon_16x16.png` …
`icon_512x512@2x.png` in a `KeyGrid.iconset` folder, then
`iconutil -c icns KeyGrid.iconset`. `rsvg-convert -w 18 -h 18 in.svg -o
out.png` is one renderer that honours the SVG's masks.

## Where errors go

The app writes to the unified log under subsystem `com.keygrid.app`,
through `os.Logger`. Read it with:

```bash
log show --last 10m --info --predicate 'subsystem == "com.keygrid.app"'
```

`NSLog` is not used: its output from the bundled app did not show up in
`log show` on macOS 26, only on stderr, which an app launched from Finder
does not have.
