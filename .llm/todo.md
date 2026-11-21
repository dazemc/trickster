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

- M: Observe every advertised `wl_seat` for idle. Bind each seat at version
  1 and create one inhibitor-aware `ext_idle_notification_v1` per seat with
  the existing 60 s timeout. Track per-seat idle state and emit the aggregate
  only when at least one seat is bound and every seat with a live
  notification is idle; a resume, seat removal, seat reset, or notifier loss
  must fall back to false. Handle late/removed seats and notifier
  removal/rebind, keep `idleSupported` true only with a notifier and at least
  one usable notification, and use the aggregate for `seatIdle`/`idleChanged`.
  Dispose every notification, seat proxy, notifier, and registry exactly
  once. Keep the observer input-free and inhibitor-free. Add native
  source-contract tests for the aggregate, per-seat notifications, late and
  removed seats, notifier rebind, and dispose. Done when analyze, full tests,
  and the release build are green.
