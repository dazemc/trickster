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

- **14.1 (S) Reset-to-default control.** Add a small circular-arrow
  `SettingsResetButton` with hover, focus, tooltip, and semantics; every
  later step reuses it. Done when component tests cover the tap firing once,
  the disabled state, and the accessible label.
- **14.2 (M) Reset on every module option.** Put a reset next to workspace
  count, clock format, CPU warn/critical, battery warn/critical, meter
  captions, and locale; each resets exactly its own field to the shipped
  default. Done when a widget test changes each option, taps its reset, and
  reads the default back from the document.
- **14.3 (M) Reset on appearance, modules, and displays.** Reset for accent
  source, custom accent, wallpaper pick, module list/order, per-module
  placement, bar edge, thickness, and output selection. Done when a widget
  test reverts each and the document round-trips the defaults.
- **14.4 (M) Drag-and-drop module order.** Replace the up/down arrows with
  a drag handle (keyboard reordering kept for accessibility), persisting
  through the same saver. Done when a widget test drags a module across
  others and the document lists the new order.
- **14.5 (S) Grey out undetectable modules.** Probe `/sys/class/power_supply`
  (injected for tests) so a battery-less system shows the Battery row
  dimmed, disabled, and explained; the control refuses changes. Done when
  tests cover present and absent probes.
- **14.6 (M) Bar display options.** User-requested additions the bar can
  honor without a new design language: `clock.show_date` (hide the date
  caption), `appearance.blur` (force the opaque fill even when the host can
  blur), and `meter.sparkline` (hide CPU/GPU history). Done when each
  renders on the bar, resets, and has config plus widget tests.
- **14.7 (M) Glass settings window.** Make the settings toplevel translucent
  (GTK RGBA visual plus translucent Flutter surfaces) so the host blurs
  behind it, with an opaque fallback when the compositor cannot. Done when
  the live window shows the blurred desktop on Hyprland and the fallback
  stays legible.
