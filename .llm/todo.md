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

## StatusNotifier offload

- **L — Implement the StatusNotifier worker path, default off.** Add the
  bounded protocol, the `trickster-sni-worker` isolate, and the UI proxy with
  icon merge; keep `TrayBloc` defaulting to the local `StatusNotifierService`.
  Done: protocol round-trip/bounds, proxy fake-worker, real-isolate fake-bus,
  and no-UI-D-Bus tests green; `flutter analyze`, full tests, and a release
  build pass; no default flip.
