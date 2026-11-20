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

- M: Rebind the PipeWire volume watcher across metadata/node/device global
  removal. Track the bound global ids, add proxy `removed`/`destroy` listeners
  that null the matching pointer and id, clear the sink map and route/volume
  state on `global_remove` without destroying a server-destroyed proxy, and
  drop watches before the core in `trickster_volume_stop`. Done when native
  source-contract tests pin the ids, listeners, removal path, and stop order;
  `flutter analyze`, full `flutter test`, and a release build are green; and
  an isolated bar survives a temporary null-sink default switch and unload
  without a crash or stale volume.
