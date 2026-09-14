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

## Phase 12 — pill glass

Denial has no blurred bar background: each pill is a translucent card with
the backdrop blurred behind its own bounds. Trickster asks the compositor
for `ext-background-effect` with the whole strip surface as the region, so
the entire band blurs. These steps move the blur to the pills and match
Denial's glass density.

- **12.1 (M) Blur only the pills.** Report each pill card's bounds per strip
  surface and set the compositor's blur region to those rectangles instead
  of the whole surface; a strip with no pills (or a host without
  `ext-background-effect`) disables the effect. Done when a widget test
  proves the reporter sends the card rectangles and clears them on unmount,
  native builds the region from the list, and the live bar shows sharp gaps
  between blurred pills.
- **12.2 (S) Match Denial's glass fills.** With the blur confined to the
  pills, lower the card fill alphas toward Denial's ~44% card opacity, and
  keep the opaque fallback when the host has no blur. Done when the live
  bar's pill density matches Denial and the no-blur path stays readable.
