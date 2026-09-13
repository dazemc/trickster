# Trickster Bar TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Every step is one action with its own done-criteria. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Phase A — feel (behaves like Denial)

- [ ] **A1 clock locale time** (S). `lib/src/bar/clock.dart`. Format the time
      from the ambient locale instead of hardcoded 24h. Done when: 12/24h
      follows locale, widget test covers both.
- [ ] **A2 clock locale date** (S). `lib/src/bar/clock.dart`. Localize the
      date caption, replacing hardcoded English months. Done when: widget
      test covers a non-English locale; minute-boundary timer untouched.
- [ ] **A3 shared action card** (S). `lib/src/bar/pill.dart`. Add
      `TricksterActionCard` mirroring Denial's `_BatteryActionCard`:
      `Semantics(button)`, tap, hover/focus highlight, accent focus ring.
      Done when: widget test covers tap + highlight states, analyzer clean.
- [ ] **A4 battery bolt in-cell** (S). `lib/src/bar/battery.dart`. Draw the
      charging bolt inside the gauge cell. Done when: bolt renders in both
      states, golden-free widget test asserts presence by state.
- [ ] **A5 battery tap action** (S). `lib/src/bar/battery.dart`. Migrate the
      pill onto `TricksterActionCard`; tap opens power settings; semantics
      label announces charge + state. Done when: tap wired, label tested.
- [ ] **A6 CPU sample series** (S). `lib/src/services/cpu.dart`. Keep a
      bounded series of recent samples (cap + test the cap). Done when:
      unit test asserts bound and ordering.
- [ ] **A7 CPU sparkline pill** (S). `lib/src/bar/cpu.dart`. Render the
      series as a sparkline `CustomPainter`, replacing `CPU 42%` text.
      Keep the `RepaintBoundary` at the call site. Done when: widget test
      asserts series→pixels mapping.
- [ ] **A8 GPU sampler service** (S). `lib/src/services/gpu.dart` (new).
      Per-GPU utilization series with stable ids, same sampler shape as CPU.
      Done when: unit test covers multi-GPU mapping and the sampler cap.
- [ ] **A9 GPU cards in strip** (S). `lib/src/bar/bar.dart` + new
      `lib/src/bar/gpu.dart`. One meter card per GPU with stable keys,
      staggered entrance like Denial's `_GpuStatusCards`. Done when: cards
      appear/disappear with the service list, widget tested.
- [ ] **A10 workspace rail widget** (M). `lib/src/bar/workspaces.dart`.
      Replace printed names with a pip rail and animated active lens
      (`AnimatedAlign`, workspace-switch curve). Done when: lens tracks the
      active id in widget tests.
- [ ] **A11 rail occupied/urgent states** (S). Same file. Derive occupied
      from backend flags; urgent styling from telemetry colors. Done when:
      all three states render distinctly, tested.
- [ ] **A12 rail click targets** (S). Same file. Migrate pips onto
      `TricksterActionCard` semantics; honor `MediaQuery.disableAnimations`.
      Done when: tap callback fires per pip, reduced-motion path tested.
- [ ] **A13 sway focus verb** (S). `lib/src/services/workspaces.dart`. Send
      `workspace` over the existing Sway socket connection. Done when:
      tested against a fake unix socket, failure logs and keeps state.
- [ ] **A14 hyprland focus verb** (S). Same file. `dispatch workspace` over
      the existing event/command sockets. Done when: same bar as A13.
- [ ] **A15 niri focus verb** (S). Same file. `focus-workspace` over the
      existing stream. Done when: same bar as A13.

## Phase B — parity (absent modules)

- [ ] **B1 StatusNotifier core** (M). New
      `lib/src/services/status_notifier.{dart,test}`. Watcher + host
      registration over D-Bus, item tracking by service name. Done when:
      unit-tested against a fake bus, disconnect cleans up.
- [ ] **B2 tray icon decode + cache** (S). Same service. Decode pixmaps at
      display size with a hard cap and eviction; never retain raw D-Bus
      byte arrays. Done when: cap/eviction unit-tested.
- [ ] **B3 tray pill + activate** (S). New `lib/src/bar/tray.dart`. Icon
      row in a pill; left-click activates; tooltips; status semantics.
      Done when: widget-tested with fake items.
- [ ] **B4 tray menus** (M). Same pill. Right-click D-Bus menus with
      submenus via `MenuController`, destructive styling, dismissal paths.
      Done when: open/navigate/dismiss tested, verified against two real
      SNI apps. XEmbed stays dropped — document why in code.
- [ ] **B5 MPRIS service** (M). New `lib/src/services/mpris.{dart,test}`.
      Player discovery, playback state, metadata; hide when no player claims
      the bus. Done when: state mapping tested against a fake player.
- [ ] **B6 media pill + controls** (S). New `lib/src/bar/media.dart`.
      Artist/title + playing state; tap reveals play/pause/next; `select`
      on available/playing only. Done when: controls drive a real player
      both ways.

## Phase C — finish

- [ ] **C1 arb pipeline + EN** (M). `lib/l10n/*.arb`, `flutter gen-l10n`
      in the build. Replace every hardcoded UI string including tooltips
      and semantics. Done when: no raw UI strings remain, EN widget tests.
- [ ] **C2 zh strings** (S). Port Denial's bar strings for clock, battery,
      tray status, workspace semantics. Done when: zh widget tests.
- [ ] **C3 blur capability probe** (S). Probe `ext-background-effect` once
      at startup, expose as a provider. Done when: tested both ways via
      override.
- [ ] **C4 pill backdrop integration** (S). `lib/src/bar/pill.dart`. Blur
      behind pills when capable, translucent fill otherwise. Done when:
      exercised on compositors with and without the protocol.
- [ ] **C5 font bundle** (S). Measure painted glyphs; bundle the JetBrainsMono
      subset (or full file if subsetting costs more than it saves). Done
      when: bundle delta recorded, pills render offline with no system fonts.
- [ ] **C6 output enumeration + selection** (S). Bootstrap + layer-shell
      platform code. Enumerate monitors, honor `outputs.conf` connector
      selection. Done when: selection logic unit-tested.
- [ ] **C7 per-output surface lifecycle** (S). Create one layer surface per
      selected monitor with independent clones; destroy dead-output surfaces
      immediately; frame work only for hosted outputs. Done when: two-monitor
      run verified, unplug/replug without restart.
- [ ] **C8 control socket transport** (S). Socket transport behind the
      existing `SettingsDocumentTransport` interface (no store changes).
      Done when: transport round-trip tested, absent socket is a clean error.
- [ ] **C9 tricksterctl status + version** (S). `bin/tricksterctl.dart`.
      Short-lived client only, never a second UI runtime. Done when: both
      commands round-trip against a live bar.
- [ ] **C10 tricksterctl reload** (S). Same binary. Re-read configs through
      the same path as the file watcher. Done when: reload applies a config
      edit end to end.
- [ ] **C11 workspace options schema** (S). `lib/src/config/settings.dart`.
      Typed `show_empty`/`max` options, validated at decode, last-good on
      invalid, watched via `select`. Template for the rest. Done when:
      round-trip tested, documented in `docs_site/content/configuration.md`.
- [ ] **C12 remaining module options** (S). CPU thresholds, clock format,
      battery warn levels, same discipline. Done when: tested + documented.
- [ ] **C13 accessibility audit** (S). Labels, values, hints, tap actions on
      everything; keyboard-only traversal of a full strip. File findings
      back here as new items.

## Packaging and release

- [ ] **P1 source PKGBUILD** (M). `packaging/arch/` source package (AOT,
      stripped, no JIT/profile artifacts); verify `session.conf` backup
      handling and first-launch `outputs.conf` seeding in-package.
- [ ] **P2 man pages** (S). Generated from `--help` output for `trickster`
      and `tricksterctl`, installed to `man1`.
- [ ] **P3 AUR -bin path** (S). Mirror Denial's split packaging for the
      release bundle.

## Decisions pending

- [ ] Lua configuration: full replacement vs. optional power layer vs.
      computed-values-only vs. stay with KEY=VALUE. Do not start without an
      explicit call.
