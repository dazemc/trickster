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
the entire band blurs. These steps moved the blur to the pills and matched
Denial's glass density.

## Phase 13 — bar zones and placement

Denial pins the tray to the strip's leading edge, centers the workspace
rail, and trails the rest. Trickster keeps every module in one trailing
cluster. These steps give the strip the same three zones and let the
settings application place each module.

## Phase 14 — settings depth

The settings window covers the bar's documents but not every knob, has no
per-option reset, orders modules with arrow buttons only, offers
hardware-dependent modules unconditionally, and is an opaque window while
the bar is glass. This phase fills the surface out.

- **14.4 (M) Reset on appearance, modules, and displays.** Reset for accent
  source, custom accent, wallpaper pick, module list/order, per-module
  placement, bar edge, thickness, and output selection. Done when a widget
  test reverts each and the document round-trips the defaults.
- **14.6 (M) Drag-and-drop module order.** Remove the up/down arrows and
  drag rows by a handle instead, reordering within their segment through
  the same saver; the Position chips keep moving a module between zones,
  and keyboard users keep a reorder path. Done when a widget test drags a
  module across its segment and the document lists the new order.
- **14.7 (M) Unavailable modules segment.** Modules whose hardware or
  configuration is absent (battery first; the probe is injectable) move to
  an "Unavailable" segment with a short reason caption each, instead of
  pretending they can be toggled. Done when a no-battery probe renders the
  row under Unavailable with its reason and tests cover both probes.
