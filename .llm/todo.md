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

## Phase 22 — settings fixes and bar interactions

- **22.2 (M) Clock calendar popup.** Clicking the clock pill opens a month
  calendar on a transient overlay surface (same lifecycle as the tray menu:
  opens toward the output's interior, closes on outside click and Escape,
  honors the accent). Done when the live bar opens the calendar from the
  clock and widget tests pin the grid, keys, and dismissal.

## Phase 23 — media visualizer

The media pill's equalizer is decorative today: MPRIS carries no audio data,
so the bars only key off play/pause. Make them real: capture the default
sink's monitor stream, analyze bands off the frame loop, and paint the bars
from the levels. No subprocesses (no `parec`/`pw-cat`); the runner links
libpipewire and streams PCM. When capture is unavailable, quiet, or the
sink is idle, the bars rest.

- **23.1 (M) PipeWire monitor capture.** The Linux runner opens the default
  sink's monitor via libpipewire (0.3) and streams raw PCM to Dart over a
  method/event channel, started and stopped on demand. Done when the live
  bar receives frames while audio plays and the stream tears down with the
  process and on stop.
- **23.2 (M) Band analysis off the frame loop.** A worker isolate turns the
  PCM frames into a small band set at ~30 Hz and a bloc exposes the levels;
  the module holds zero timers and zero subscriptions while no media plays.
  Done when levels move with music, fall to rest on silence, and a unit test
  pins the mapping from synthetic frames to levels.
- **23.3 (S) Bars from levels.** The pill's equalizer paints the bloc's
  band levels instead of the synthetic loop, keeping the static rest when
  capture is unavailable; reduced motion still freezes the bars. Done when
  the live bars track the music and widget tests pin the level mapping.
