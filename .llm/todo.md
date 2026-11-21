# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criterion. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

The `.llm/` reinitialization does **not** authorize performance, refresh,
memory, or lifecycle work. Findings in `.llm/suggestions.md` remain proposals
until the user escalates them here.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Telemetry modules

- **M — Add the first-class disk module.** Add `DiskSample`/`DiskSampler`
  over one configured mount with statvfs in a worker isolate, `DiskBloc`,
  `DiskOptions`, the `disk` pill/options/l10n/status, and the ModuleScope
  idle gate. The module is default-on and hides when the mount is missing or
  unreadable. Done: statvfs math/real `/` read/sampler/pill/config/gating/
  status/l10n tests, `flutter analyze`, full `flutter test`, and a release
  build pass; headless status proof replaces the screen-off visual check.
