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

- L: Offload MPRIS only to a widget-free worker isolate. Introduce a
  `MediaPlayerClient` interface implemented by `MediaPlayerService` and a new
  proxy. The worker owns `MediaPlayerService` and its `DBusClient`, listens
  to snapshots, and sends JSON-compatible `MprisPlaybackState.toJson()` plus
  errors. The UI proxy starts the worker only when media starts, forwards
  start (including paused), pause/resume recovery, play/pause, next, and
  previous commands, ignores pre-start controls, and kills the worker and
  closes its streams on dispose with no revival. Leave StatusNotifier on the
  UI isolate. Keep `MediaBloc`/bar behavior unchanged; adapt ModuleScope and
  media service builder types. Add tests for command forwarding, state
  deserialization, paused start, recovery pause/resume, disposal, worker
  error/failure, and that the UI proxy constructs no DBusClient. Done when
  analyze, full tests, and the release build are green.
