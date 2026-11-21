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

## Memory modules

- **M — Add the first-class RAM module.** Add `RamSample`/`RamSampler`
  (`/proc/meminfo`, 1 Hz, 45-sample history, paused start, idle pause/resume),
  `RamBloc`, `RamOptions`, the `ram` module row/pill, settings options,
  en/zh strings, and `tricksterctl status` state. RAM is default-on and hides
  when no reading exists. Done: sampler/pill/config/gating/status tests,
  `flutter analyze`, full `flutter test`, and a release build pass; headless
  runtime proof replaces the screen-off visual check.
