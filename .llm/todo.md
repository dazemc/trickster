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

- M: Recover MPRIS after session-bus transport loss, mirroring the landed
  StatusNotifier pattern. Add an injectable client factory, a single-flight
  rebuild with 1s→30s backoff and connection generations, `onError` for the
  owner and PropertiesChanged streams, and transport-error routing from
  refresh/player calls. The rebuild cancels subscriptions, clears the active
  player, emits unavailable, closes the old client, creates a new one,
  re-subscribes owner changes, and refreshes discovery. Keep the 60s recovery
  refresh and add no other polling. Done when in-process `DBusServer` tests
  cover stop/recreate, post-reconnect title changes, cold start with the bus
  down then up, bounded retries, and dispose; existing MPRIS tests and
  analyze/full tests are green.
