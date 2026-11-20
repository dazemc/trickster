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

- S: Preserve the settings last-good snapshot across a `.prev` recovery.
  `FileSettingsTransport.write` must atomically snapshot the in-memory
  `_lastGood` document to `.prev` before replacing the live file, never copy
  the possibly corrupt live file. Done when a corrupt live plus good `.prev`
  revision 1 reads 1, a write to revision 2 leaves live 2 and `.prev` 1,
  repeated writes keep `.prev` one revision behind, no `.prev.tmp` remains,
  and `flutter analyze` plus `flutter test` are green.
