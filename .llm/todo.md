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

1. **Settings save and state consistency** (M). Make threshold controls keep a
   strict step at every endpoint and reset; flush debounced settings edits on
   page switch, options collapse, and close; serialize the settings bloc's
   document events; surface revision conflicts instead of overwriting the
   latest disk document; recover `.prev` through unreadable candidate reads in
   both bootstrap and the settings store; round-trip settings-app output
   geometry; guard availability probes; and correct the fallback docs. Done
   when `flutter analyze`, `flutter test`, and the release build pass.
2. **Settings modules and outputs correctness** (M). Deduplicate configured
   module names and isolate unknown names so the bar and settings page cannot
   render duplicate keys; keep unplugged output selections and never collapse
   a partial selection to all outputs; reload external `outputs.conf` changes
   without clobbering an unsaved preview; and close the remaining field
   gaps from the layout pass. Done when `flutter analyze`, `flutter test`, and
   the release build pass.
