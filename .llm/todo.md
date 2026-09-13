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


## Phase 8 — settings application (Denial parity)

The bar stopped at "no settings window in v1"; the user replaced that with
a standalone settings application. It is its own Flutter process and bundle
(`trickster-settings`), speaks to the running bar over the control socket
(file transport as fallback), and covers exactly the settings the bar has.
The version stays 0.1.0 until the user calls a bump.

- [ ] **8.1 settings app scaffold** (M). `settings_app/`. A standalone
      Flutter Linux app with its own runner and bundle, depending on the
      `trickster` package for theme tokens, motion, and the localized
      catalog; one window, no strip surfaces, no bar blocs. Done when: it
      builds and opens a window painted in the shell's design language.
- [ ] **8.2 control transport wiring** (S). `settings_app/`. Read and write
      the settings document through `SocketSettingsTransport`
      (`settings.read`/`settings.write`), surfacing revision conflicts and
      last-good errors. Done when: a test round-trips a document over a fake
      socket and reports a conflict without losing data.
- [ ] **8.3 appearance page** (M). Accent presets plus the HSV wheel from
      Denial's settings, writing `accent` and following live bar updates.
      Done when: picking a color writes the document and the bar reloads it.
- [ ] **8.4 modules page** (S). Enable, disable, and reorder the configured
      module list. Done when: membership and order round-trip through the
      document and the bar rebuilds its providers.
- [ ] **8.5 displays page** (M). Per-output side, thickness, and selection
      through the `system_bar=` grammar, with the live output list. Needs an
      `outputs.read`/`outputs.write` control command (or a watched-file
      transport) because the socket serves settings only today. Done when:
      saving writes outputs.conf and the bar reconciles its surfaces.
- [ ] **8.6 module options page** (M). The typed options the bar already
      decodes: workspaces `show_empty`/`max`, clock format, CPU and battery
      thresholds, meter captions. Done when: every control round-trips and
      the bar applies it live.
- [ ] **8.7 language page** (S). Add a `locale` key to settings.json, honor
      it in the bar's scope resolver, and switch the app catalog live. Done
      when: bar and app follow the saved language without a restart.
- [ ] **8.8 about page** (S). Bar and protocol versions plus repository
      links, degrading cleanly when the bar is not running. Done when: it
      reads versions from a live bar and from a stopped one.
- [ ] **8.9 packaging** (M). The Arch package builds and installs the second
      bundle with a `trickster-settings.desktop`; extend the AUR recipe and
      the version-sync test to the app. Done when: the package installs both
      binaries and the desktop entry opens the app.
