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

## OpenCode usage

- **OpenCode pill and strip wiring (S).** Render the configured module: `OpencodePill` with the headline Go meter, percent, and session cost; a localized hover label with weekly/monthly, remaining, reset, and token detail; one conditional provider in `ModuleScope`, one guarded builder in `TricksterBarStrip`, and the `tricksterctl status` state entry. Done when widget and gating tests cover shown, hidden-without-server, and disabled states, and `flutter analyze` + `flutter test` are green.

- **OpenCode settings, strings, and docs (S).** Add the module to the settings catalog and options panel (headline meter, session cost), English and Chinese strings, and the Modules/Configuration doc rows; verify the settings gear round-trips `opencode` options. Done when `flutter analyze` + `flutter test` are green and the docs describe the data source and options.
