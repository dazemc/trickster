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

- [ ] **6.1 direct tray icon sources** (S). `lib/src/services/status_notifier.dart`.
      `IconName` values that are absolute paths or `file://` URIs, and items
      whose only asset is SVG, still render the placeholder. Add the
      direct-path arm and an SVG rasterizer. Done when: both arms are tested
      against fake items and a real item needs neither.
- [ ] **6.2 single --check implementation** (S). `lib/main.dart`,
      `linux/runner/my_application.cc`. The native runner intercepts `--check`
      before the Dart entrypoint starts, so Dart's `_check` is dead and can
      drift. Delete the dead path (or route the native flag through Dart) so
      the diagnostics have one owner. Done when: `--check` output is
      unchanged and one implementation remains.

## Decisions pending

- [ ] Lua configuration: full replacement vs. optional power layer vs.
      computed-values-only vs. stay with KEY=VALUE. Do not start without an
      explicit call.
