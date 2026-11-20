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

- M: Recover the StatusNotifier tray after session-bus transport loss. Rebuild
  the `DBusClient` instead of re-listening on the poisoned match-rule
  refcounts; inject the client factory; coalesce all transport errors into one
  single-flight recovery with 1s→30s backoff; recreate the watcher endpoint
  and subscriptions; preserve registered addresses; clear stale items and
  pending refreshes; re-register/refresh; and make dispose cancel every timer
  and subscription without reviving. Add a cheap `GetId` heartbeat only for
  drop detection. Done when in-process `DBusServer` tests cover stop/recreate,
  cold start with the bus down then up, post-reconnect signal delivery,
  bounded retries, and dispose; analyze/full tests are green.
