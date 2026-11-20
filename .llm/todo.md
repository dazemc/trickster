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

- S: Tear down overlay surfaces from their owning blocs. Add `close()`
  overrides to the tray menu, calendar, volume slider, and tooltip blocs that
  bump their generation, close the current native overlay surface, absorb a
  dead-channel error, and then close the bloc. Harden each `*ViewsRetained`
  handler so a session whose view is no longer retained is cleared while its
  view-id set is trimmed. Done when each bloc close closes its native overlay,
  a retained event without the session view clears it, an already-destroyed
  surface does not throw, and `flutter analyze` plus `flutter test` are green.
