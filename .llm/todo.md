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

- M: Recover the MPRIS worker after isolate death. `MediaPlayerWorkerProxy`
  respawns only while started, with 1 s→30 s bounded backoff, a single-flight
  spawn, and no respawn before start or after dispose. Preserve the
  recovery-paused flag so a respawn resends `start(paused: true)` when the
  seat was idle-paused; later pause/resume still forward. On isolate
  error/exit or startup failure: fail pending requests, cancel the old
  event/error/exit subscriptions, kill and close the dead connection, emit
  unavailable, then retry. Never respawn for a normal worker command error or
  an in-worker D-Bus failure. Reset the backoff after a valid state snapshot.
  Done when tests prove exit→unavailable→respawn→state and controls, preserved
  paused state, bounded retries, dispose cancelling the retry, no pre-start
  spawn, and analyze/full tests/release build are green.
