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

## Authorized step

- S: Honor reduced motion in every timed transition. Add one shared helper
  around `MediaQuery.maybeDisableAnimationsOf` and apply it to the
  `SystemBarEntrance` stagger (settle the controller, schedule no timer), the
  clock `AnimatedSwitcher`, the meter `AnimatedDefaultTextStyle`, the media
  control `AnimatedContainer`, and the settings transitions in `app.dart`,
  `color_wheel.dart`, `appearance.dart`, and `settings_theme.dart`. Install
  `MediaQuery.fromView` in the settings root so that process sees the
  platform flag. Do not remove animation controllers or change normal-motion
  timings. Add widget tests under `MediaQueryData(disableAnimations: true)`
  for immediate rest with no transient frames, keep the normal-motion suite
  green, and pass analyze, the full test suite, and the release build. Done
  when both processes honor the flag and the tests prove it.
