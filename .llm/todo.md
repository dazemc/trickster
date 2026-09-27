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

## Phase 23 — media visualizer

The media pill's equalizer is decorative today: MPRIS carries no audio data,
so the bars only key off play/pause. Make them real: capture the default
sink's monitor stream, analyze bands off the frame loop, and paint the bars
from the levels. No subprocesses (no `parec`/`pw-cat`); the runner links
libpipewire and streams PCM. When capture is unavailable, quiet, or the
sink is idle, the bars rest.

- **23.3 (S) Bars from levels.** The pill's equalizer paints the bloc's
  band levels instead of the synthetic loop, keeping the static rest when
  capture is unavailable; reduced motion still freezes the bars. Done when
  the live bars track the music and widget tests pin the level mapping.

## Phase 24 — sink volume

The media pill shows no volume today: the host's own keys and mixers are the
only way to change the default sink. Show the level and let the pill set it.

- **24.1 (M) Sink volume over PipeWire.** The runner watches the default
  sink (WirePlumber's `default.audio.sink` metadata), reads its channel
  volumes, and pushes changes over the capture channel; a bloc exposes the
  level and a setter, so external changes (host keys, wpctl) follow live.
  Done when the live bar logs sink volume changes and a probe set updates
  `wpctl get-volume`.
- **24.2 (S) Volume percentage in the media pill.** The pill paints the
  sink's level beside the transport keys; the label disappears with the
  pill and starts no work of its own. Done when the live percentage matches
  `wpctl get-volume` and a test pins the label mapping.
- **24.3 (M) Volume slider on click.** Clicking the percentage opens a
  slider on a transient overlay surface (the calendar/tray-menu lifecycle:
  anchored and clamped, outside-click and Escape dismissal, hosted-blur
  choice honored), and dragging sets the sink volume live. Done when the
  live slider moves the sink and widget tests pin the drag mapping and
  dismissal.
