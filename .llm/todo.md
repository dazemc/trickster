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

- [ ] **4.3 blur capability probe** (S). Probe `ext-background-effect` once
      at startup, expose as a provider. Done when: tested both ways via
      override.
- [ ] **4.4 pill backdrop integration** (S). `lib/src/bar/pill.dart`. Blur
      behind pills when capable, translucent fill otherwise. Done when:
      exercised on compositors with and without the protocol.
- [ ] **4.5 font bundle** (S). Measure painted glyphs; bundle the JetBrainsMono
      subset (or full file if subsetting costs more than it saves). Done
      when: bundle delta recorded, pills render offline with no system fonts.
- [ ] **4.6 output enumeration + selection** (S). Bootstrap + layer-shell
      platform code. Enumerate monitors, honor `outputs.conf` connector
      selection. Done when: selection logic unit-tested.
- [ ] **4.7 per-output surface lifecycle** (S). Create one layer surface per
      selected monitor with independent clones; destroy dead-output surfaces
      immediately; frame work only for hosted outputs. Done when: two-monitor
      run verified, unplug/replug without restart.
- [ ] **4.8 per-output workspace focus** (S). `lib/src/services/workspaces.dart`
      + rail wiring. Workspace state is monitor-global: `j/activeworkspace`
      marks only the focused monitor's workspace and focus targets the
      current monitor, so a second surface's rail is wrong. Carry the active
      workspace per output (`j/monitors`, Sway `visible`, niri output). Done
      when: unit tests assert the mapping, lens verified per output.
- [ ] **4.9 control socket transport** (S). Socket transport behind the
      existing `SettingsDocumentTransport` interface (no store changes).
      Done when: transport round-trip tested, absent socket is a clean error.
- [ ] **4.10 tricksterctl status + version** (S). `bin/tricksterctl.dart`.
      Short-lived client only, never a second UI runtime. Done when: both
      commands round-trip against a live bar.
- [ ] **4.11 tricksterctl reload** (S). Same binary. Re-read configs through
      the same path as the file watcher. Done when: reload applies a config
      edit end to end.
- [ ] **4.12 workspace options schema** (S). `lib/src/config/settings.dart`.
      Typed `show_empty`/`max` options, validated at decode, last-good on
      invalid, watched via `select`. Template for the rest. Done when:
      round-trip tested, documented in `docs_site/content/configuration.md`.
- [ ] **4.13 remaining module options** (S). CPU thresholds, clock format,
      battery warn levels, and meter caption source (generic CPU/GPU tags
      vs queried device names), same discipline. Done when: tested +
      documented.
- [ ] **4.14 accessibility audit** (S). Labels, values, hints, tap actions on
      everything; keyboard-only traversal of a full strip. File findings
      back here as new items.
- [ ] **4.15 MPRIS stale-signal guard** (S). `lib/src/services/mpris.dart`.
      The dbus package installs signal matches without awaiting the bus, so
      a change emitted right after discovery can be lost until the recovery
      scan. Done when: a test emits before the match installs and the
      service converges without a second signal.
- [ ] **4.17 tray tooltips** (S). `lib/src/bar/tray.dart`. Hover tooltips on
      a transient overlay surface, reusing the menu-surface mechanism;
      semantics stay as the accessible path. Done when: hover show/hide and
      dismissal verified on the live session.
- [ ] **4.18 menu surfaces across compositors** (S). `trickster_menu_surface_new`
      and `TrayMenuSurface`. Anchor math is Hyprland-verified only; check
      placement and dismissal on Sway, niri, and river. Done when: each
      opens the menu below the strip and every dismissal path works.
- [ ] **4.19 Hyprland IPC contract** (S). `.llm/performance.md`. The
      worker-isolate rule for `.socket.sock` (connect+write in one turn; the
      strip surface hands off before engine start) exists only as code
      comments. Promote it to a standing performance contract and point
      `lib/src/services/workspaces.dart` at it. Done when: the contract is
      in the note and the code references it.
- [ ] **4.20 bloc widget-test contract** (S). `docs_site/content/development.md`,
      `test/`. Seed states via constructors, let providers own bloc
      lifecycle, assert disposal with a close flag, and never await
      `pumpEventQueue` under FakeAsync — today duplicated as test comments.
      Document the contract and extract the shared pump harness used by
      `widget_test.dart` and `gating_test.dart`. Done when: the docs section
      and harness exist and both suites are green.

## Phase 5 — packaging and release

- [ ] **5.1 source PKGBUILD** (M). `packaging/arch/` source package (AOT,
      stripped, no JIT/profile artifacts); verify `session.conf` backup
      handling and first-launch `outputs.conf` seeding in-package.
- [ ] **5.2 man pages** (S). Generated from `--help` output for `trickster`
      and `tricksterctl`, installed to `man1`.
- [ ] **5.3 AUR -bin path** (S). Mirror Denial's split packaging for the
      release bundle.

## Decisions pending

- [ ] Lua configuration: full replacement vs. optional power layer vs.
      computed-values-only vs. stay with KEY=VALUE. Do not start without an
      explicit call.
