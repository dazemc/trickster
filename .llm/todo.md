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

1. **Settings layout and module coverage pass** (M). Prove the modules page at
   900x600, 1280x800, and 1920x1080 with real surfaces; add edge auto-scroll to
   module drags and cover keyboard reorder; scroll an opened options panel into
   view, paint a Scrollbar, and cap the content width; add disk-path and
   network-interface resets with field/document sync; keep options reachable
   for disabled modules and prune their expanded state; add temperature, disk,
   network, and keyboard-layout availability reasons; carry the cheap meter
   semantics, focus, text-scale, and workspace tint-reset fixes. Done when
   `flutter analyze`, `flutter test`, and the release build pass and the
   settings, modules, and performance notes are current.
