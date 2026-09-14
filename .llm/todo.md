# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criteria. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Phase 1 — Bloc migration

Riverpod → `flutter_bloc`, explicit events and states, no Cubits. Every
state class ships `toJson`/`fromJson` from day one (convention only, no
HydratedBloc) so `tricksterctl status` and agent runtime review read real
state later. Debug/profile builds run a verbose `BlocObserver`
(transitions + create/close + errors + timing) to stderr; release stays
silent per the logging rules.

## Phase 2 — feel (behaves like Denial)

## Phase 3 — parity (absent modules)

## Phase 4 — finish


## Phase 5 — packaging and release


## Phase 6 — follow-ups


## Phase 7 — version sync


## Phase 9 — parity and release hygiene

## Phase 8 — settings application (Denial parity)

The bar stopped at "no settings window in v1"; the user replaced that with
a settings application: the same binary run in settings mode
(`trickster-settings`), its own process and engine with no strip surfaces,
writing through the running bar's control socket (file transport as
fallback) and covering exactly the settings the bar has. The version stays
0.1.0 until the user calls a bump.

## Phase 10 — docs and install hygiene

## Phase 11 — workspace rail parity

Denial v0.4.0 renders the workspace rail as a centered, numbered card in the
strip with a liquid active lens. Trickster keeps its compositor-fed
workspaces and module gate; these steps align the presentation.

- **11.4 (M) Show the Denial workspace count on every rail.** Denial's
  indicator always shows a fixed 1..N count on every monitor, with
  active/occupied relative to that output; Trickster's per-output filter
  hides a monitor's workspace 1 from the other strip. Add a
  `workspace_count` option (2-9, default 4) and render 1..count on every
  strip, resolving active/occupied from compositor state and switching (or
  creating) through the backend; retire `show_empty`/`max` through a
  decode-compatible transition. Done when both monitors' rails show the
  full count, a widget test covers the per-output active/occupied mapping,
  and the live multi-monitor session matches.
- **11.3 (M) Deform the active lens on switch.** Port
  `_WorkspaceActiveLens`: scale 1 → 1.34 → 0.94 → 1 across
  `workspaceIndicatorTakeoff` 72ms / `Travel` 168ms / `Settle` 80ms with the
  MD3 emphasized accelerate/decelerate curves, honoring reduced motion; add
  the tokens and curves to `lib/src/theme/motion.dart`. Done when a widget
  test observes the sequence, reduced motion skips it, and the live bar
  matches Denial's motion.
