# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

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

- [ ] **2.8 GPU cards in strip** (S). `lib/src/bar/bar.dart` + new
      `lib/src/bar/gpu.dart`. One meter card per GPU with stable keys,
      staggered entrance like Denial's `_GpuStatusCards`. Done when: cards
      appear/disappear with the service list, widget tested.
- [ ] **2.9 workspace rail widget** (M). `lib/src/bar/workspaces.dart`.
      Replace printed names with a pip rail and animated active lens
      (`AnimatedAlign`, workspace-switch curve). Done when: lens tracks the
      active id in widget tests.
- [ ] **2.10 rail occupied/urgent states** (S). Same file. Derive occupied
      from backend flags; urgent styling from telemetry colors. Done when:
      all three states render distinctly, tested.
- [ ] **2.11 rail click targets** (S). Same file. Migrate pips onto
      `TricksterActionCard` semantics; honor `MediaQuery.disableAnimations`.
      Done when: tap callback fires per pip, reduced-motion path tested.
- [ ] **2.12 sway focus verb** (S). `lib/src/services/workspaces.dart`. Send
      `workspace` over the existing Sway socket connection. Done when:
      tested against a fake unix socket, failure logs and keeps state.
- [ ] **2.13 hyprland focus verb** (S). Same file. `dispatch workspace` over
      the existing event/command sockets. Done when: same bar as 2.11.
- [ ] **2.14 niri focus verb** (S). Same file. `focus-workspace` over the
      existing stream. Done when: same bar as 2.11.

## Phase 3 — parity (absent modules)

- [ ] **3.1 StatusNotifier core** (M). New
      `lib/src/services/status_notifier.{dart,test}`. Watcher + host
      registration over D-Bus, item tracking by service name. Done when:
      unit-tested against a fake bus, disconnect cleans up.
- [ ] **3.2 tray icon decode + cache** (S). Same service. Decode pixmaps at
      display size with a hard cap and eviction; never retain raw D-Bus
      byte arrays. Done when: cap/eviction unit-tested.
- [ ] **3.3 tray pill + activate** (S). New `lib/src/bar/tray.dart`. Icon
      row in a pill; left-click activates; tooltips; status semantics.
      Done when: widget-tested with fake items.
- [ ] **3.4 tray menus** (M). Same pill. Right-click D-Bus menus with
      submenus via `MenuController`, destructive styling, dismissal paths.
      Done when: open/navigate/dismiss tested, verified against two real
      SNI apps. XEmbed stays dropped — document why in code.
- [ ] **3.5 MPRIS service** (M). New `lib/src/services/mpris.{dart,test}`.
      Player discovery, playback state, metadata; hide when no player claims
      the bus. Done when: state mapping tested against a fake player.
- [ ] **3.6 media pill + controls** (S). New `lib/src/bar/media.dart`.
      Artist/title + playing state; tap reveals play/pause/next; `select`
      on available/playing only. Done when: controls drive a real player
      both ways.

## Phase 4 — finish

- [ ] **4.1 arb pipeline + EN** (M). `lib/l10n/*.arb`, `flutter gen-l10n`
      in the build. Replace every hardcoded UI string including tooltips
      and semantics. Done when: no raw UI strings remain, EN widget tests.
- [ ] **4.2 zh strings** (S). Port Denial's bar strings for clock, battery,
      tray status, workspace semantics. Done when: zh widget tests.
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
- [ ] **4.8 control socket transport** (S). Socket transport behind the
      existing `SettingsDocumentTransport` interface (no store changes).
      Done when: transport round-trip tested, absent socket is a clean error.
- [ ] **4.9 tricksterctl status + version** (S). `bin/tricksterctl.dart`.
      Short-lived client only, never a second UI runtime. Done when: both
      commands round-trip against a live bar.
- [ ] **4.10 tricksterctl reload** (S). Same binary. Re-read configs through
      the same path as the file watcher. Done when: reload applies a config
      edit end to end.
- [ ] **4.11 workspace options schema** (S). `lib/src/config/settings.dart`.
      Typed `show_empty`/`max` options, validated at decode, last-good on
      invalid, watched via `select`. Template for the rest. Done when:
      round-trip tested, documented in `docs_site/content/configuration.md`.
- [ ] **4.12 remaining module options** (S). CPU thresholds, clock format,
      battery warn levels, same discipline. Done when: tested + documented.
- [ ] **4.13 accessibility audit** (S). Labels, values, hints, tap actions on
      everything; keyboard-only traversal of a full strip. File findings
      back here as new items.

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
