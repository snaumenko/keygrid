---
name: Bug report
about: Something KeyGrid did, or did not do, that it should have
title: ""
labels: []
---

**What you pressed**
The shortcut, or the menu item.

**What happened**
What the window, the Dock or the menu did. "Nothing" is a valid answer.

**What you expected**

**Your setup**
- macOS version (Apple menu → About This Mac):
- Keyboard shape: ANSI (US, wide Return key) or ISO (European, tall Return key):
- Displays: how many, how arranged (side by side, stacked), any in portrait:
- KeyGrid version (menu bar icon → About KeyGrid):
- Signed with (the About window says "Signed by …" or "Signed ad hoc"):

**Log lines**
Run this right after reproducing and paste the lines that mention the
shortcut or the problem:

```
/usr/bin/log show --last 10m --predicate 'subsystem == "com.keygrid.app"'
```

**Config**
If you changed `~/.config/keygrid/config.json`, paste the relevant part.
