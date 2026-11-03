# KeyGrid

[![CI](https://github.com/snaumenko/keygrid/actions/workflows/ci.yml/badge.svg)](https://github.com/snaumenko/keygrid/actions/workflows/ci.yml)

Keyboard-first window tiler and Dock switcher for macOS. One app, no
network, no dependencies.

KeyGrid puts windows onto a grid and apps out of the Dock from the
keyboard, which is all the name means. It is one small app you build
and sign yourself: it talks to nothing, phones nobody, keeps its
settings in one text file, and asks for exactly one permission. The
source is short enough to read, and that is the point: the owner
described what he wanted and reviewed every line, an AI wrote the Swift,
and the comments are written for a reader with no Swift background.

## Everything it does

Every shortcut below is a default and can be changed in the config file.
⌃⌥ is Control+Option.

| Keys | What happens |
| --- | --- |
| ⌃⌥\` | Finder comes forward (macOS pins it first in every Dock) |
| ⌃⌥1 … ⌃⌥9 | the 1st to 9th Dock icon after Finder comes forward; a stopped app launches |
| ⌃⌥0 | the 10th icon after Finder, the 11th in the Dock |
| ⌃⌥⏎ | the window in front fills the display; pressed again, it goes back where it was |
| ⌃⌥[ and ⌃⌥] | left or right half; pressed again on that half, the same half's opposite on the display on that side |
| ⌃⌥\ | centered on its display, size unchanged |
| ⌃⌥⇧\ | centered with an equal gap on all four sides |
| ⌃⌥← → ↑ ↓ | move the window one grid cell; at the display's edge, onto the display beyond |
| ⌃⌥⇧← → ↑ ↓ | push one edge of the window one grid cell; at the edge, the opposite edge |
| ⌃⌥, and ⌃⌥. | previous or next display, keeping the window's place and size as fractions |
| ⌃⌥Space | a grid over the display under the mouse; click a cell or drag a rectangle to place the window; Escape, ⌃⌥Space again or switching apps cancels |

After a Dock switch a border in the accent colour flashes around the
window that came forward, so the eye finds it. The menu bar icon is a
health light and its menu holds the rest: the Accessibility state, the
config file, Launch at Login, About, Quit (see The menu).

## The details

**Dock switcher.** ⌃⌥\` (the key left of 1) brings Finder
forward, which macOS pins first in every Dock. ⌃⌥1 to ⌃⌥9 bring the 1st
to 9th icon after Finder, counting left to right exactly as the Dock
shows them; running apps that are not pinned, and "recent applications",
count where they appear. ⌃⌥0 is the 10th after Finder, the 11th icon.
The keys sit \` 1 … 9 0 along the top row, so the Nth key is the Nth icon.
The backtick is a key position, not a character: on a US (ANSI)
keyboard with another layout active it is still the key left of 1,
whatever it prints. On an ISO keyboard, the European shape with the
tall Return key, that key code belongs to the key between left Shift
and Z, and that key is Finder; the key left of 1 (`§` on most of them)
has another code that KeyGrid does not bind. A stopped app
launches. When the app was already running, a
border in the system accent colour appears along the edge of its focused
window the moment it comes forward and fades within a second, so the eye
finds the window on a crowded display or on the other one; a launching
app, whose first window comes up on its own time, gets no border. The
modifiers are configurable and the border can be turned off; every
built-in default holds ⌃⌥, because ⌘1 to ⌘9 switch tabs in most browsers
and a global shortcut takes the key away from the app in front.

**Window sweeps, moves and placements.** Four shortcuts push one edge of the window in
front, one grid cell at a time, over the same grid the overlay draws
(12×6 on a 16:9 display, see Grid placement). ⌃⌥⇧← moves the window's
left edge one column to the left, so the window grows; once that edge
is at the display's edge, the same shortcut moves the right edge left
instead, so the window shrinks against the edge, down to one column. An
edge that is between grid lines moves onto the next line first. →, ↑ and
↓ do the same on their side. From the right half, six presses of ⌃⌥⇧←
reach the full width and eleven more leave a one-column strip on the
left. Four more shortcuts, ⌃⌥ with the same arrows, move the whole
window one cell that way, size unchanged. At the display's edge a move
carries the window onto the display on that side, if there is one,
against its near edge and the same size in grid cells; with no display
there it does nothing. ⌃⌥, and ⌃⌥. (the keys with `<` and `>` on their
caps) jump the window to the previous or next display in one press from
anywhere on its display, counting displays left to right and wrapping
at both ends; the window keeps its place and size as fractions of the
display, so a left half stays a left half, clamped to fit. With one
display they do nothing and the log says so. Five placements are one
press: full, left half,
right half, on ⌃⌥ with Return and the bracket keys; center, ⌃⌥\, which
keeps the window's size and puts it in the middle of its display; and
center at two thirds, ⌃⌥⇧\, which fills the display's visible area
minus the same gap on all four sides, one sixth of the shorter edge
rounded to whole points (on a landscape display with the default grid,
about one grid row above and below and the same points left and right).
A half pressed
again on a window that already is that half puts it on the display on
that side as that display's near half, so ⌃⌥[ on a left half puts the
window on the left display as its right half, and a third press makes
it the left half there. The frame is
the display's visible area, so the menu bar and the Dock are never
covered. Every shortcut is configurable; these are the defaults:

| Action       | Default    | What it does                                     |
| ------------ | ---------- | ------------------------------------------------ |
| `full`       | ⌃⌥ Return  | the whole visible area; pressed again, back to where the window was |
| `leftHalf`   | ⌃⌥ [       | left half; already there, onto the display to the left |
| `rightHalf`  | ⌃⌥ ]       | right half; already there, onto the display to the right |
| `center`     | ⌃⌥ \       | the middle of the display, size unchanged        |
| `centerTwoThirds` | ⌃⌥⇧ \ | the middle, with an equal gap on all four sides  |
| `sweepLeft`  | ⌃⌥⇧ ←      | left edge one column left; at the edge, right edge left |
| `sweepRight` | ⌃⌥⇧ →      | right edge one column right; at the edge, left edge right |
| `sweepUp`    | ⌃⌥⇧ ↑      | top edge one row up; at the edge, bottom edge up |
| `sweepDown`  | ⌃⌥⇧ ↓      | bottom edge one row down; at the edge, top edge down |
| `moveLeft`   | ⌃⌥ ←       | one column left; at the edge, onto the display to the left |
| `moveRight`  | ⌃⌥ →       | one column right; at the edge, onto the display to the right |
| `moveUp`     | ⌃⌥ ↑       | one row up; at the edge, onto the display above |
| `moveDown`   | ⌃⌥ ↓       | one row down; at the edge, onto the display below |
| `previousDisplay` | ⌃⌥ ,  | onto the display to the left in left-to-right order, same place and size as fractions; wraps |
| `nextDisplay`     | ⌃⌥ .  | onto the display to the right in left-to-right order, same place and size as fractions; wraps |

`full` is a toggle: the first press remembers where the window was and
fills the display; the next press, while the window still fills it (or
still has whatever slightly smaller frame it settled for, as a Terminal
window does), puts the window back exactly where it was, even if that is now on
another display or partly off screen because the displays were
rearranged in between. The memory lives in the running app only, the
last 32 windows, and is empty after a relaunch, so ⌃⌥⏎ on a window
that already fills its display then does nothing and the log says
`window.full ignored: the window already fills its display and no
earlier frame is remembered`. A window moved or resized by hand after
a fill is no longer full, so the next press fills it again and
remembers that newer frame instead.

A sweep that can go no further (the window is one cell wide against that
edge), a move at an edge with no display beyond it, or a half pressed
again with no display on that side, does nothing and the log says so. A window that refuses the exact frame, because it has a
minimum size or a fixed aspect ratio, keeps what it accepts; the log
says what it kept. The top and bottom halves, the quarters, the
three-quarters and the other-display shortcut of version 0.3 are gone;
the sweeps, the moves and the grid cover them.

**Grid placement.** ⌃⌥ Space dims the display under the mouse and
draws a grid over its visible area: 6 cells along the display's shorter
edge and as many along the longer edge as keeps the cells roughly square,
12×6 on a 16:9 display and 6×12 on the same display turned to portrait.
The cell under the mouse lights
up; click one cell, or drag across several, and on release the window
that was in front when you pressed the shortcut moves into that
rectangle. Escape, ⌃⌥ Space again, switching to another app, or a
change in the display arrangement closes the grid without moving
anything. The grid is on the display under the
mouse, not the window's, so a drag on the other display carries the
window there. The size and the shortcut are configurable; a half dragged
on the grid is exactly the frame ⌃⌥[ or ⌃⌥] places, and the sweep and
move shortcuts step along the same lines.

**The menu bar icon** is a health light. The nine-dot board means all is
well; the board with a badge in its corner means the Accessibility
permission is missing (the first menu item then offers **Grant
Accessibility…**); the board with a filled disc with an exclamation mark cut out of it in that
corner means the config file could not be loaded or some shortcuts could not be
registered, and a grayed line in the menu names the problem. For a
broken file it reads, for example, `Config error: grid.size: 7 is not
one of 6, 12, 18, 24, 30, 36`; a very long message is cut with `…`, and
the log line (which also names the file) has it whole. For shortcuts that
could not be registered it names the first, `Shortcut failed:
window.full: …`, with `(+2 more)` when there are more; the log has them
all. A missing permission takes the icon, but the error line stays so a
broken file is not hidden.

**Launch at login.** The menu item **Launch at Login** adds KeyGrid to
macOS's own Login Items list, the one System Settings → General → Login
Items & Extensions shows, and the checkmark says whether it is there.
macOS may ask you to allow the item once in that pane; the menu item
says so and opens the pane when clicked. Turn it on from the copy in
`/Applications` (`make install`): the login item points at the bundle
that was running when you turned it on, and `dist/KeyGrid.app` from
`make run` is replaced by the next build.

Coming next: a preferences window.

## Install

Requirements: macOS 14 or newer and the Apple Command Line Tools
(`xcode-select --install`). No Xcode, no developer account.

```bash
git clone https://github.com/snaumenko/keygrid ~/p/keygrid
cd ~/p/keygrid
make install
open /Applications/KeyGrid.app
```

On every launch until it is granted, macOS asks for the **Accessibility**
permission. Grant it
in System Settings → Privacy & Security → Accessibility. The menu-bar
icon loses the badge in its corner within two seconds (it shows the
exclamation mark instead if the config file also has a problem). Quit
any other window-management or Dock utility bound to the same keys, or
move its keys: two apps acting on one shortcut both act.

KeyGrid lives in the menu bar only. There is no Dock icon.

## The menu

The icon at the top right is a health light: the nine-dot board when
all is well, the board with a badge in its corner when the Accessibility
permission is missing, the board with a filled disc and an exclamation
mark when the config file or a shortcut has a problem (The details,
above, says what each means). Under it:

- **Accessibility: granted**, a line of status; or **Grant
  Accessibility…**, which opens System Settings at Privacy & Security →
  Accessibility.
- A grayed line naming the current problem, when there is one:
  `Config error: …` or `Shortcut failed: …`.
- **Open Config File**: opens `~/.config/keygrid/config.json` in the
  app macOS uses for `.json` files.
- **Reload Config**: re-reads the file now. Saving the file does the
  same within a second; the item is for when you want to be sure.
- **Launch at Login**: a checkmark when KeyGrid is in macOS's Login
  Items list; click to add or remove it. If macOS wants you to allow the
  item, the title says so and the click opens the Login Items pane.
- **About KeyGrid**: the version the bundle was built with, the four
  promises from What this app never does, the config file's path,
  whether Accessibility is granted, who signed the running copy ("Signed
  ad hoc" explains a permission that keeps disappearing; see Signing
  and the Accessibility prompt), a link to this repository, and the
  license.
- **Quit KeyGrid** (⌘Q while the menu is open).

## Configuration

Settings live in one file, `~/.config/keygrid/config.json`
(or `$XDG_CONFIG_HOME/keygrid/config.json`). KeyGrid writes it on
first launch with these contents:

```json
{
  "version": 1,
  "dock": {
    "enabled": true,
    "modifiers": "ctrl+alt",
    "highlight": true
  },
  "window": {
    "full": "ctrl+alt+return",
    "leftHalf": "ctrl+alt+[",
    "rightHalf": "ctrl+alt+]",
    "center": "ctrl+alt+\\",
    "centerTwoThirds": "ctrl+alt+shift+\\",
    "sweepLeft": "ctrl+alt+shift+left",
    "sweepRight": "ctrl+alt+shift+right",
    "sweepUp": "ctrl+alt+shift+up",
    "sweepDown": "ctrl+alt+shift+down",
    "moveLeft": "ctrl+alt+left",
    "moveRight": "ctrl+alt+right",
    "moveUp": "ctrl+alt+up",
    "moveDown": "ctrl+alt+down",
    "previousDisplay": "ctrl+alt+,",
    "nextDisplay": "ctrl+alt+."
  },
  "grid": {
    "hotkey": "ctrl+alt+space",
    "size": 6
  }
}
```

The file is the whole truth. A section that is not in the file is off: no
`dock` section means no Dock shortcuts, no `window` section means no
window shortcuts, no `grid` section means no grid. `version` is
reserved; leave it. Nothing is stored anywhere but the file: no
UserDefaults, no cache. The one thing the app remembers that is not in
the file lives only in memory and is gone when it quits: the frames
windows had before ⌃⌥⏎ filled them, so a second ⌃⌥⏎ can put them back.
Launch at login is not a setting of KeyGrid's either: the menu item
adds or removes an entry in macOS's own Login Items list, which System
Settings shows and can change without KeyGrid. Until the file format
is frozen, a decision that comes after v1.0, a new version may add keys;
delete the file to get a fresh default, or add the keys by hand.

### Dock

- `dock.enabled`: `false` turns the Dock shortcuts off, so the keys reach
  the front app again.
- `dock.modifiers`: the keys held with the backtick or digit. Names: `cmd` (or
  `command`), `ctrl` (or `control`), `alt` (or `opt`, `option`), `shift`,
  joined with `+`, for example `"cmd"`. Case does not matter. At least
  one is required. ⌘ with a digit switches tabs in most browsers, which
  is why the default is ⌃⌥.
- `dock.highlight`: `false` turns off the border drawn around the focused
  window of the app a Dock shortcut brings forward. Missing, it is on.

### Window shortcuts

Each key under `window` is an action name from the Window sweeps and
moves table (`full`, `leftHalf`, `rightHalf`, `center`,
`centerTwoThirds`, `sweepLeft`, `sweepRight`, `sweepUp`, `sweepDown`,
`moveLeft`, `moveRight`, `moveUp`, `moveDown`, `previousDisplay`,
`nextDisplay`);
its value is the shortcut as text: one or more modifiers
and exactly one key, joined with `+`, for example `"ctrl+alt+shift+left"`
or `"cmd+shift+f"`. Case does not matter. The modifier names are the ones
`dock.modifiers` takes. The key names are:

- letters `a` to `z`, and digits `0` to `9` on the top row (the numeric
  keypad has other codes and is not supported);
- `return`, `tab`, `space`, `escape`, `left`, `right`, `up`, `down`;
- `[`, `]` and `\`, the three keys right of P on a US keyboard, `,`
  and `.`, the two right of M, and `` ` ``, the key left of 1. In the
  file a backslash is written `\\`, as JSON requires: `"ctrl+alt+\\"`;
- `f1` to `f20`.

To leave an action without a shortcut, delete its line or set it to
`null`. An action name that is misspelled is ignored as an unknown key,
so that action is unbound too. The log line `applied config: …`, written
at launch and after every reload that changes the settings, lists every
unbound action.

The action names of version 0.3 that no longer exist (`topHalf`,
`bottomHalf`, the four quarters, `leftThreeQuarters`,
`rightThreeQuarters`, `otherDisplay`) are not ignored: a file that still
binds one is refused, the log names it and what took over, for example
`window.topHalf was replaced by window.sweepUp and window.sweepDown;
remove window.topHalf`, and the previous settings stay in force. Delete
those lines or set them to `null`.

Two shortcuts bound to the same keys, in any section, are an error: give
both `leftHalf` and `sweepLeft` the value `"ctrl+alt+["` and the log line
ends with `ctrl+alt+[ is bound twice: window.leftHalf, window.sweepLeft`. A
shortcut without a modifier is an error too. Like every config error it
keeps the previous settings in force.

### Grid

- `grid.hotkey`: the shortcut that shows the grid, written like a window
  shortcut (`"ctrl+alt+space"`). Delete the line or set it to `null` to
  have a grid section with no shortcut.
- `grid.size`: one number, how many cells fit along the shorter edge of
  a display. Missing, it is 6.

  Picture a display as a sheet of squared paper. `size` says how many
  squares run along its short side. The long side gets as many squares
  as keeps them roughly square: `size` scaled by how much longer the
  long side is, rounded to the nearest multiple of 6, never fewer than
  6. Multiples of 6 because a half and a third of the display then
  always land on a line, in both directions. Each display is worked out
  on its own, from its own shape, and a display turned to portrait gets
  the same grid turned on its side.

  With the default 6: a 16:9 or 16:10 display gets 12 columns by 6
  rows; 4:3 gets 6×6; an ultrawide 21:9 gets 12×6 too (14 rounds down
  to 12); a 32:9 super-ultrawide gets 24×6; a 9:16 portrait display gets
  6 columns by 12 rows. `"size": 12` is twice as fine everywhere: 24×12
  on 16:9. The accepted values are 6, 12, 18, 24, 30 and 36; 36 on a
  1600-point-tall display still leaves 44-point cells, which a mouse can
  hit. The grid overlay draws these cells, and the moves and sweeps
  step along the same lines, so a half dragged on the grid is exactly
  the frame ⌃⌥[ places.

  Any other number is an error; the log line ends with `grid.size: 7 is
  not one of 6, 12, 18, 24, 30, 36`, and the previous settings stay in
  force like after every config error. The `columns` and `rows` fields
  of version 0.3.0 are gone; a file that still has one is refused with
  `grid.columns was replaced by grid.size; remove grid.columns`.

The grid places the window that was in front when the shortcut was
pressed. A config edit that changes the settings closes a showing grid
without moving anything and without a log line.

### Reloading and errors

Edits take effect within a second of saving; no restart. A broken file is
logged (the `/usr/bin/log show` command in this section finds the line)
and the previous settings stay in
force until you fix it. The menu item **Reload Config** re-reads the file
by hand, and **Open Config File** opens it in the app macOS uses for
`.json` files.

The system log keeps every line at the `notice` and `error` levels:
config errors (malformed JSON with its line and column, a bad value with
the name of its field), every shortcut that did nothing (`ignored:` with
the reason), a Dock switch whose border could not be drawn (`no border;`
with the reason: the app has no focused window after a second read 0.3
seconds later, or did not come to the front within 1.5 seconds), the
`applied config:` line, a grid closed by Escape, a
second press of its shortcut, another app coming to the front, or a
display change (`grid cancelled:` with the reason), and a window that
kept a different frame than asked. The full path
`/usr/bin/log` matters: zsh, the default shell, has a builtin named `log`
that answers `log show` with "too many arguments".

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.keygrid.app"'
```

Successful loads and moves are logged at the `info` level, which macOS
does not keep on disk. To watch them, run this in a second terminal
before saving, pressing **Reload Config**, or moving a window:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "com.keygrid.app"'
```

## Signing and the Accessibility prompt

`make install` signs the app ad hoc, which needs no certificate. macOS
ties the Accessibility grant to that signature, and an ad-hoc signature
changes on every rebuild, so after each `make install` you may have to
grant the permission again.

To grant it once and keep it, make a free self-signed certificate:
Keychain Access → Certificate Assistant → Create a Certificate, name
any name you like (below, `<certificate name>` stands for it), type
**Code Signing**. Then build with it:

```bash
SIGN_IDENTITY="<certificate name>" make install
```

`make run` takes the same variable and launches `dist/KeyGrid.app`
without installing it.

### Resetting the grant

To see the first-launch prompt and the badged icon again, as when
checking a build, remove the grant and relaunch:

```bash
tccutil reset Accessibility com.keygrid.app && pkill -x KeyGrid; open dist/KeyGrid.app
```

`tccutil` is part of macOS and needs no `sudo` for your own apps. The
grant is per code signature, so a bundle signed with a different
identity (or ad hoc) shows up as a separate entry in System Settings;
`tccutil reset` clears them all for the bundle identifier.

## Troubleshooting

- **A shortcut does nothing, and the menu bar icon has a badge.** The
  Accessibility permission is missing. Grant it in System Settings →
  Privacy & Security → Accessibility; the badge goes within two seconds.
  If you granted it before and it keeps disappearing, the app is signed
  ad hoc and every rebuild is a new signature to macOS: About KeyGrid
  says "Signed ad hoc". Make a self-signed certificate and build with
  `SIGN_IDENTITY` (Signing and the Accessibility prompt).
- **A shortcut does nothing, and the log says `ignored:`.** The reason
  follows the word: no focused window (click a window first), the
  window is already at the edge, only one display is attached, and so
  on. Read the log with the command in Reloading and errors.
- **A shortcut does something else, or two things.** Another utility
  owns the key. If KeyGrid could not register it, the menu shows
  `Shortcut failed: window.full: …`: quit the other utility or change
  the key in one of them. If both registered it (apps that watch the
  keyboard through an event tap can), both act; change the key in one.
- **The icon shows an exclamation mark.** The config file has a
  problem; the grayed menu line names it, and the previous settings
  stay in force until you fix the file. `Config error: grid.size: 7 is
  not one of 6, 12, 18, 24, 30, 36` means what it says; a JSON error
  comes with a line and column.
- **Launch at Login is on but KeyGrid did not start.** macOS may be
  waiting for you to allow it: open System Settings → General → Login
  Items & Extensions. Or the item points at a bundle that no longer
  exists, because it was turned on from `dist/KeyGrid.app` and the
  folder was rebuilt; turn it off and on again from the copy in
  `/Applications`.
- **⌃⌥\` does nothing on a European keyboard.** On ISO keyboards that
  key code sits between left Shift and Z; press ⌃⌥ with that key.

## What this app never does

- No network code of any kind. No telemetry, no update checks.
- No third-party dependencies. Nothing downloaded at build time either.
- No permission other than Accessibility. Never Input Monitoring, Screen
  Recording, Notifications, Automation, or Full Disk Access.
- No settings anywhere but `~/.config/keygrid/config.json`.

You can check the no-network and no-dependency claims yourself. The first
command prints nothing but its message; the second prints nothing, because
`Package.swift` has no package-level `dependencies:` list (the two
`dependencies: ["KeyGridCore"]` lines inside it name the app's own
library target, not a package):

```bash
grep -riE "URLSession|NSURLConnection|import Network" Sources || echo "no network code"
grep -n "^    dependencies:" Package.swift
```

## Checking a build

Start from a fresh clone (`git clone`, `make install`, grant
Accessibility when asked). With two displays if you have them, in the
order below:

1. ⌃⌥\` brings Finder forward. ⌃⌥1 to ⌃⌥9 bring the 1st to 9th Dock
   icons after Finder forward, as shown left to right, including a
   running app that is not pinned. Each time, a border in the accent colour appears along
   the edge of the app's focused window and fades out. Press the shortcut
   of the app already in front: the border appears again. With two
   displays and the app's window on the second one, the border is there.
   Close every Finder window, click the desktop, and press ⌃⌥\`: the
   Dock opens a Finder window and the border appears around it a moment
   later. Quit an app that keeps running with no window (Messages after
   ⌘W), press its shortcut: no border, and the log shows `dock.N: no
   border; <the app's name> has no focused window`. Set `"highlight":
   false` in the config and save: the switch works and no border appears.
   Set it back.
2. Open an unpinned app: the numbering shifts with the Dock.
3. ⌃⌥N for a pinned app that is not running launches it, with no border
   around the window it opens.
4. ⌃⌥0 activates the 11th icon, the 10th after Finder.
5. With Safari in front and two tabs open, ⌘1 still reaches Safari (the
   first tab, or the first Favorites bookmark, whichever its Tabs
   setting picks): KeyGrid's defaults leave ⌘ alone. Set
   `"enabled": false` in the config and save: ⌃⌥1 does nothing. Set it
   back.
6. Revoke Accessibility in System Settings: the icon gains its corner
   badge within two seconds and the menu offers **Grant Accessibility…**, which
   opens System Settings at Privacy & Security → Accessibility. Re-grant:
   the icon returns.
7. **Open Config File** opens the file. With the `/usr/bin/log stream`
   command from Reloading and errors running, **Reload Config** prints
   `…/config.json loaded`. Set `"size": 7` in the grid section and save:
   within a second the menu bar icon shows an exclamation mark in its
   corner and the menu has a grayed `Config error: grid.size: 7 is not
   one of 6, 12, 18, 24, 30, 36` line. Set it back: the mark and the line
   go. Bind two actions to the same keys: the line reads `Config error:
   ctrl+alt+1 is bound twice: dock.2, window.full` (with your keys and
   fields). With Accessibility revoked and the file still broken, the
   icon is badged and the error line is still there.
8. **About KeyGrid** opens a window in front of whatever was there, with
   the version from `Resources/Info.plist`, "Signed by <certificate name>" for
   a build made with `SIGN_IDENTITY` and "Signed ad hoc" for a plain
   `make run`, and the config file's path; the link opens the repository
   in the browser; closing the window puts the app that was in front
   back in front.
9. From the copy in `/Applications`, **Launch at Login** gains its
   checkmark (allow it in System Settings → General → Login Items &
   Extensions if the item says so; KeyGrid is then listed there); log
   out and in: KeyGrid is running. Click it again: the checkmark goes,
   the entry leaves the list, and after a logout KeyGrid is not running.
   From `dist/KeyGrid.app` the log shows `launch at login registers
   …/dist/KeyGrid.app; a bundle outside /Applications …`.
10. With a TextEdit window in front, ⌃⌥⏎, ⌃⌥[ and ⌃⌥] put it where the
    table says. The two halves meet exactly with no gap and no overlap.
    Drag the window somewhere odd, ⌃⌥⏎ fills the display, ⌃⌥⏎ again
    puts it back exactly where it was. Quit and relaunch KeyGrid, fill
    the window by ⌃⌥⏎, and press again: nothing moves and the log shows
    `window.full ignored: the window already fills its display and no
    earlier frame is remembered`.
    Drag the window to a corner and press ⌃⌥\: it is centered on the
    display at the same size. ⌃⌥⇧\: it fills the display with the same
    gap on all four sides, the top and bottom gaps about one grid row deep.
    With two displays side by side and the window on the right one, ⌃⌥[
    once makes it the left half; ⌃⌥[ again puts it on the left display as
    that display's right half; ⌃⌥[ a third time makes it the left half
    there, and a fourth press does nothing, with the log showing
    `window.leftHalf ignored: leftHalf can go no further; the window is
    at the left edge of its display and no display is there`.
11. From ⌃⌥] (the right half), press ⌃⌥⇧← six times: the window grows a
    column at a time to the full width. Press it once more: the right
    edge moves left one column. Ten more presses leave a one-column
    strip; the next press changes nothing and the log shows
    `window.sweepLeft ignored: sweepLeft can go no further; the window is
    already one grid cell wide against that edge`. ⌃⌥⇧→, ⌃⌥⇧↑
    and ⌃⌥⇧↓ do the same on their side.
12. ⌃⌥[ for the left half, then ⌃⌥→: the window keeps its width and
    moves one column right; ⌃⌥↑ and ⌃⌥↓ do nothing with a full-height
    window and the log shows `window.moveUp ignored: moveUp can go no
    further; the window is at the top edge of its display and no display
    is there`. With two displays side by side, ⌃⌥→ pressed repeatedly
    carries the window onto the right display against its left edge,
    six columns wide; ⌃⌥← carries it back onto the first display,
    against that display's right edge. ⌃⌥[ for the left half, then
    ⌃⌥.: the window is the left half of the display to the right; ⌃⌥.
    again wraps it back to the first display; ⌃⌥, goes the other way.
    With one display the log shows `window.nextDisplay ignored: only one
    display is attached`.
13. Drag the window so its left edge is between two grid lines (⌃⌥ Space
    shows them), then ⌃⌥⇧←: the edge lands on the next line to the left,
    less than a full column away.
14. With System Settings in front, ⌃⌥⇧← repeatedly asks for a width it
    is too narrow for; the log shows a `kept … instead of …` line.
15. Revoke Accessibility and press ⌃⌥[: nothing moves, and the log shows
    `window.leftHalf ignored: Accessibility permission is not granted; use Grant Accessibility… in the menu`.
16. With a TextEdit window in front and the mouse over its display,
    ⌃⌥ Space dims that display and draws the grid; the cell under the
    mouse follows it. Click one cell: the window fills that cell. Press
    again and drag from one corner cell to another, then the reverse
    way: the window fills the same rectangle both times.
17. ⌃⌥ Space, then Escape; ⌃⌥ Space twice; ⌃⌥ Space, then ⌘Tab to
    another app. Each closes the grid and moves nothing, and the log
    shows `grid cancelled:` with `Escape was pressed`, `the grid hotkey
    was pressed again`, and `<the other app's name> came to the front`.
18. With two displays, move the mouse to the display the window is not
    on and drag a rectangle: the window moves to that display.
19. Set `"size": 12` and save: the next grid is twice as fine, 24×12 on
    a 16:9 display. Set `"size": 7` and save: the log shows `grid.size:
    7 is not one of 6, 12, 18, 24, 30, 36` and the grid stays 24×12. Set
    the size back to 6. With a display in portrait, the grid there is
    6×12 while the landscape one shows 12×6.
20. Close every Finder window, click the desktop, and press ⌃⌥ Space:
    nothing appears, and the log shows `grid.hotkey ignored: Finder has
    no focused window`.

## License

MIT License with the Commons Clause; the text is in [LICENSE](LICENSE).
In short: anyone may read, build, use, copy and modify KeyGrid, at
home or at work, free or for pay, and give copies away, but may not
sell it or a product whose value comes substantially from it. The
software comes as is, with no warranty. Contributions are taken under
the plain MIT License, as [CONTRIBUTING.md](CONTRIBUTING.md) explains,
so that the owner keeps the right to offer KeyGrid commercially.

## Changelog

- **1.0.0**: the first public release.

## More

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): building, tests, dev setup.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the pieces fit.
- [docs/DESIGN.md](docs/DESIGN.md): the design the app was built from.
- [CONTRIBUTING.md](CONTRIBUTING.md): reports, code, and the license of
  contributions.
