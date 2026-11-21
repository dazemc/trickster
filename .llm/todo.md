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

## Current

- **Slice A — GPU/VRAM correctness.** Follow symlinked
  `/sys/class/drm/cardN` in discovery and availability; reconfigure the shared
  GPU/VRAM sampler on live `gpu`/`vram` changes; remove unsupported i915/Xe
  VRAM paths and claims; amend APU carveout docs; stop fabricating 0% for
  active NVIDIA cards and refresh a previously missing NVIDIA name. Done:
  symlink, live-toggle, and suspended-NVIDIA tests green; analyze clean;
  release build; docs corrected.
- **Slice B — Meter boundaries and terminal samplers.** Keep `warn < critical`
  at RAM/VRAM/temperature slider ends and resets; make `start()` after
  `dispose()` terminal for RAM, temperature, and GPU. Done: boundary and
  start-after-dispose tests actually reach the ends and pass; analyze clean;
  release build.
