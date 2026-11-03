# Security

KeyGrid is a small macOS menu-bar app that moves windows and switches
Dock apps from the keyboard. It has no network code, no dependencies,
and asks for one permission, Accessibility, which it needs to read the
Dock and move other apps' windows. The whole source is in this
repository and is meant to be read.

## Reporting a problem

If you find a way KeyGrid could be made to do something its owner did
not intend (act on keys it should not, write outside
`~/.config/keygrid/`, reach the network, escalate what the Accessibility
grant allows), report it privately through GitHub's **Report a
vulnerability** button on the Security tab of this repository. That
opens a private advisory only the owner can read. Do not open a public
issue for it.

Say what you did, what happened, and the macOS version. A copy of the
relevant lines from
`/usr/bin/log show --last 10m --predicate 'subsystem == "com.keygrid.app"'`
helps.

## What to expect

One person maintains KeyGrid in their spare time. You will get an answer
within two weeks, usually sooner. A fix ships as a normal commit and
release; the advisory is published when the fix is out, with credit to
you unless you ask otherwise.

## What is in scope

The app as built from this repository with `make install`. Problems in
macOS itself, in the Command Line Tools, or in other apps are not
KeyGrid's to fix, but a report is still welcome if KeyGrid makes them
worse.
