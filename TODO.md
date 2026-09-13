# Trickster Bar TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Check items off as they land — do not let it rot.

## Phase A — feel (behaves like Denial)

- [ ] Interactive pills everywhere: `Semantics` + tap targets + hover/focus
      highlight on every pill, mirroring Denial's `_BatteryActionCard` and
      `_WorkspaceIndicatorButton` shapes.
- [ ] Workspace rail: pip rail with animated active lens, occupied-vs-empty
      states, replacing printed names.
- [ ] Click-to-focus workspaces: focus command per backend (Sway
      `workspace`, Hyprland dispatch, niri `focus-workspace`).
- [ ] Meter sparklines: CPU pill becomes a sample-series meter like Denial's
      `_MeterModule`; add per-GPU cards.
- [ ] Battery action: charging bolt in-cell; tap opens power settings.
- [ ] Clock localization: localized time/date via the arb pipeline, replacing
      hardcoded English months and 24h time.

## Phase B — parity (absent modules)

- [ ] System tray (StatusNotifier): port Denial's `StatusNotifierService`
      (pure D-Bus); left-click activate, right-click D-Bus menus with
      submenus, tooltips, status semantics. XEmbed stays dropped.
- [ ] Media (MPRIS): port the playback service; pill shows artist/title and
      playing state; tap reveals play/pause/next controls.

## Phase C — finish

- [ ] Localization pass: semantics labels on everything, arb pipeline (EN
      first, zh with Denial's strings).
- [ ] Backdrop blur where the host advertises `ext-background-effect`;
      translucent fill otherwise. Never fake blur.
- [ ] Fonts: bundle JetBrainsMono (or the measured subset the pills paint).
- [ ] Per-output surfaces: one layer surface per monitor with independent
      clones; destroy dead-output surfaces immediately.
- [ ] Control plane: `tricksterctl status|reload|version` over
      `$XDG_RUNTIME_DIR/trickster/control.sock`; socket transport behind the
      existing settings-store interface.
- [ ] Per-module options objects (workspace `show_empty`/`max` first, then
      cpu thresholds, clock format, battery warn levels), validated at
      decode, last-good on invalid.
- [ ] Accessibility audit against the finished bar.

## Packaging and release

- [ ] Source `trickster-bar` PKGBUILD; `-bin` AUR path mirroring Denial's
      split packaging (AOT, stripped, no JIT/profile artifacts).
- [ ] Man pages for `trickster` and `tricksterctl`.
- [ ] `/etc/trickster/session.conf` as a `backup=`-preserved template.

## Decisions pending

- [ ] Lua configuration: full replacement vs. optional power layer vs.
      computed-values-only vs. stay with KEY=VALUE. See plan discussion;
      do not start without an explicit call.
