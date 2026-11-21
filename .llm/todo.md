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

## Authorized step

- M: Make `*Stopped` terminal for `CpuBloc`, `GpuBloc`, `BatteryBloc`,
  `MediaBloc`, `TrayBloc`, `WorkspacesBloc`, and `OpencodeBloc`. Mark the
  bloc stopped, cancel its snapshots subscription, dispose the underlying
  sampler/service/monitor/worker exactly once, and ignore later
  Started/Paused/Resumed/Sample/Focus/Refresh events. `close()` after a stop
  stays safe and does not dispose twice; close without a stop keeps the
  current teardown. No production path emits `Stopped` yet. Done when tests
  cover each bloc's single dispose, ignored later samples and starts, and
  close-after-stop; analyze/full tests/release build are green.
