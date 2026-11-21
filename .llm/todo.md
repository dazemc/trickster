# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criterion. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

The `.llm/` reinitialization does **not** authorize performance, refresh,
memory, or lifecycle work. Findings in `.llm/suggestions.md` remain proposals
until the user escalates them here.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Input modules

- **M — Add the first-class Hyprland keyboard-layout module.** Add
  `KeyboardLayoutState`/`HyprlandKeyboardLayout`, the event-driven
  `.socket2.sock` `activelayout` subscription with reconnect, the
  `KeyboardLayoutBloc`, the `keyboard_layout` pill/settings/l10n/status, and
  the ModuleScope provider. It is default-on, Hyprland-only, and creates no
  sockets when the backend is unavailable. Done: fixture devices JSON,
  event/reconnect/multi-keyboard tests, bloc/pill/gating/status/l10n tests,
  `flutter analyze`, full `flutter test`, and a release build pass; headless
  status proof replaces the screen-off visual check.
