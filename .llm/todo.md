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

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Phase: correctness and lifecycle hardening

- S: Keep live config reload alive across watch-stream errors and closes. Done
  when an errored/closed directory watch resubscribes with backoff and dispose
  cancels all restarts.

- S: Close all band-analyzer ports when worker startup fails. Done when a
  forced startup failure returns false with zero open ReceivePorts and a
  following start still works.

- S: Destroy the cairo input regions used by the tooltip and bootstrap windows.
  Done when a release build passes and both surfaces remain click-through with
  no unmatched cairo_region_create in the runner.

## Phase: shell capabilities

- M: Pause nonessential 1 Hz work while the seat is idle via ext-idle-notify-v1.
  Done when native emits idle/resume, the CPU/GPU samplers stop while idle and
  take one fresh sample on resume, the clock keeps ticking, --check reports
  the protocol, and a release build plus live run are clean.
