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

- M: Retry the control listener after an accept error. Track the accept
  subscription, handle `onError`/`onDone` with a bounded 500ms→30s backoff,
  single-flight start/retry, `_stopping`, and no retry after dispose. A retry
  rebinds safely: preserve `_ownsSocket`, never unlink a live foreign socket,
  and close a socket bound during dispose instead of leaking it. Add a
  testable listener-error seam. Done when tests prove an error triggers a
  retry that serves requests again, dispose cancels retries and removes the
  owned path, a live second owner is not stolen, and no timers survive
  dispose; analyze/full tests/release build are green.
