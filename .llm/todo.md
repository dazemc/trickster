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
- [ ] **4.21 keyboard tray menu** (S). `lib/src/bar/tray.dart`. The audit
      left the tray context menu pointer-only; bind a keyboard path (Menu
      key or Shift+F10) to open it for the focused item, and keep the
      pointer route unchanged. Done when: the menu opens from the keyboard
      in a test and on the live session.

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
