# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criteria. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## OpenCode usage window

- **OpenCode pill opens the usage window (S).** Clicking the pill launches the `opencode-usage` companion app (found via `$XDG_BIN_HOME`, `$HOME/.local/bin`, `/usr/local/bin`, `/usr/bin`, or `PATH`), falling back to the workspace console URL when it is not installed; add the launcher, hint changes, tests, and docs. Done when the launcher order is unit-tested, the bar tests stay green, the app window opens from the installed bar, and `flutter analyze` + `flutter test` pass.
