# Contributing to KeyGrid

KeyGrid is a one-person project. The owner builds it, signs it and
reads every line, because the point of the app is that a person can
trust it. That shapes how contributions work.

## Reports and ideas

Bug reports, questions and feature ideas are welcome as GitHub issues.
A good report says what you pressed, what happened, what you expected,
and the lines from
`/usr/bin/log show --last 10m --predicate 'subsystem == "com.keygrid.app"'`.
Many fixes are written by the owner from a report rather than taken as
a patch.

## Code

Code changes start as an issue, so the design is agreed before anything
is written. Pull requests are accepted at the owner's discretion and
may be declined, rewritten, or closed without being merged, even when
they work. `CLAUDE.md` describes the conventions the code follows and
the review every change goes through.

## License of contributions

KeyGrid is released under the MIT License with the Commons Clause
(see `LICENSE`): anyone may use, copy and modify it, free or paid, but
may not sell it. The Commons Clause binds everyone who receives the
software, the owner included for code that is not the owner's. So that
the owner keeps the right to offer KeyGrid commercially, code from
others comes in under the plain MIT License, without the Commons Clause.
By opening a pull request you agree that:

1. You own the copyright to the code you submit, or you have the right
   to submit it under these terms. Code copied from elsewhere, or
   written for an employer who owns your work, is not yours to submit.
2. Your contribution is licensed to the project and to the owner under
   the MIT License, without the Commons Clause.
3. You receive no compensation and keep your copyright. You may use
   your own contribution however you like outside KeyGrid.

The pull request template asks you to confirm this with a checkbox. A
pull request without the confirmation is not merged.

## Code written with AI tools

Code produced with an assistant is fine to submit if you reviewed it and
can stand behind point 1 above. Say so in the pull request.
