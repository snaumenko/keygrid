# KeyGrid — agent instructions

Small macOS menu-bar utility: Dock switcher (⌃⌥\` for Finder, ⌃⌥1…⌃⌥9, ⌃⌥0 for the ten icons after it), window
move and sweep hotkeys (⌃⌥ arrows move the window one grid cell, across
displays at the edge; ⌃⌥⇧ arrows push one edge), full and half
placements (⌃⌥ Return, [ and ]), and a grid-placement overlay.
One app the owner builds and signs himself. Design:
`docs/DESIGN.md`.

## Hard rules (trust is the point of this project)

- No network code of any kind. No telemetry, no update checks.
- No third-party dependencies. Zero SwiftPM packages, nothing vendored.
- Only the Accessibility permission. Never request Input Monitoring,
  Screen Recording, Notifications, Automation, or Full Disk Access.
- All settings live in `~/.config/keygrid/config.json`. Nothing in
  UserDefaults or other hidden state.
- The command-line build (`make`) must always work with Command Line
  Tools alone. Xcode is optional for editing/debugging; never require
  it or a paid Apple Developer account.

## Conventions

- All active work documents (designs, plans, notes) go in `docs/work/`.
  Do not use `docs/plans/` or `docs/superpowers/`.
- Swift, AppKit first; SwiftUI only for the preferences window.
- Keep code small and plainly commented: the owner has no Swift
  background and reads the source to audit it.
- Comments must stand on their own for a reader with zero context. Never
  write "the same", "this", "as above", or point at something the reader
  has not seen. Name the thing. A story that spans several types goes in
  `docs/ARCHITECTURE.md`, not scattered across comments.
- Every type opens with a doc comment that says what it is, what it is
  for, and what it does not do.
- Pure logic (frame math, grid selection, config parsing, hotkey string
  parsing, coordinate conversion) lives in functions with unit tests,
  separate from AppKit/AX glue.
- Swift 5 language mode under the Swift 6 toolchain.

## Build and test

SwiftPM package with a Makefile (see design doc for targets):
`make`, `make test`, `make run`, `make install`, `make clean`.
Tests use Swift Testing (`import Testing`), never XCTest: XCTest is not
in the Command Line Tools. Always run tests through `make test`, which
adds the framework paths SwiftPM misses without Xcode.

Day-to-day loop on the owner's machine:

- Build, sign and launch: `SIGN_IDENTITY="<certificate name>" make run`,
  with the name of the owner's self-signed code-signing certificate.
  The bundle is `dist/KeyGrid.app` (gitignored). Always pass the
  identity: an ad-hoc signature changes on every build and loses the
  Accessibility grant.
- Reset the Accessibility grant (to see the prompt and the badged icon):
  `tccutil reset Accessibility com.keygrid.app && pkill -x KeyGrid;
  open dist/KeyGrid.app`.
- Read the app's log: `/usr/bin/log show --last 10m --predicate
  'subsystem == "com.keygrid.app"'` (full path: zsh has a `log`
  builtin).
- Quit the running copy before relaunching: `pkill -x KeyGrid`.
  `make run` does this itself.

## Dev workflow

1. Pick a GitHub issue (`gh issue list`).
2. Create a branch named `<issue-number>-<slug>`, for example `1-scaffold`.
3. Use the `superpowers:brainstorming` skill to write the task's design
   and implementation plan in `docs/work/`.
4. Implement.
5. Code review (see "Code review" below).
6. Review the comments as a separate pass (see "Comment review" below).
7. Open a PR that closes the issue. The body opens with a plain-language
   summary and a "How to review" section listing the files in reading
   order.
8. After the PR merges, clean up locally: delete the branch and pull
   `main`.

If the change is large and splits into independent pieces, split it and
stack the PRs. Decide this during the brainstorming session.

### Code review

Done after the implementation compiles and `make test` passes, before
the comment review and the PR. Run the `pr-review-toolkit:review-pr`
skill on the branch diff against `main`. It dispatches fresh reviewers
for correctness, silent failures, test coverage, type design, and
comment accuracy, each with no memory of the implementation session.

Give the reviewers the task doc in `docs/work/` and this file. Beyond
their usual checks, they verify the hard rules at the top of this file:
no network code, no new framework import under `Sources/KeyGridCore/`,
no state outside the config file, no permission other than
Accessibility.

Fix what they find in its own commit. A finding that changes a
load-bearing decision in the plan is not fixed locally: update the plan
first, then the code.

### Comment review

Done after the implementation compiles and tests pass, before the PR.
Re-read every comment in the diff pretending to have zero context: no
knowledge of the other files, the plan, or the conversation.

For each comment ask:

- Can a reader who landed here cold understand it? Words like "the
  same", "this", "that", "as above", "see earlier" mean no. Name the
  thing instead.
- Does it rely on a story told somewhere else? If the story spans
  several types, write it once in `docs/ARCHITECTURE.md` and have the
  comment name the concept, not retell or allude to the story.
- Does every type open with what it is, what it is for, and what it does
  not do?
- Are magic numbers and copied constants explained with their source
  (for example `cmdKey = 0x0100` from Apple's `Events.h`)?
- Would the comment still be true after the next task lands? Avoid
  "for now" and "later" unless the comment names the task.

Repetition between comments is acceptable; a pointer that makes the
reader jump is not. Fix the comments in a commit of their own so the
reviewer can see code and prose changes apart.
