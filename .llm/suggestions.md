# Trickster suggestions

Agent-proposed, user-reviewed suggestions. If you see something the queue,
the constitution, or the code gets wrong — a missed Denial parallel, a
performance trap, a config wart, a docs gap — propose it here so the next
session sees it. Standing rules and instructions belong in `AGENTS.md`, not
here.

## Rules

- Entries must be **absolutely needed**: they prevent a future mistake,
  unblock queued work, or record a decision with its reason. Brainstorming,
  nice-to-haves, and restatements of `.llm/todo.md` do not belong here.
- One entry per issue. Keep it to five lines: what, where, why, and what
  to do about it.
- Append after every change: review the touched code for misses and add
  entries that meet the bar; findings never live only in the transcript.
- Remove an entry in the same change that resolves it — same discipline as
  `.llm/todo.md`.
- After finishing any `.llm/todo.md` step, re-read this file and update it, but
  only if something meets the bar above. No obligatory edits. Silence is a
  valid review outcome.
- At a phase boundary, walk every open entry with the user and settle its
  decision — keep, condense, move, escalate, or dismiss — before the next
  phase starts.

## Open suggestions

- **Hyprland blocks its main loop on fresh `.socket.sock` connections.**
  `hyprCtlFDTick` accepts one, then polls up to 5s; a UI-isolate client
  that flushes a turn later deadlocks the wait and tears down the layer
  surface. Keep queries and `dispatch` connect+write-adjacent on a worker
  isolate (`workspaces.dart`); hand off the surface before engine start.
- **FakeAsync deadlocks on the bloc event loop.** In widget tests, awaiting
  `pumpEventQueue()` after `bloc.add()` or `bloc.close()` hangs: bloc's
  pipeline needs real event-loop turns. Seed via constructors, let
  `BlocProvider(create:)` own lifecycle, and assert disposal with a close
  flag on an injected subclass — no `bloc-` transcript under FakeAsync.
- **Workspace state is monitor-global, not per output.** The Hyprland join
  uses `j/activeworkspace`, so only the focused monitor's workspace is
  marked focused and `focusWorkspace` targets the current monitor. The
  per-output rails of 4.7 need the active workspace per output
  (`j/monitors`, Sway `visible`, niri output) before they can be correct.
  (`lib/src/services/workspaces.dart`.)
- **Workspace sockets never reconnect.** All three backends swallow
  `onError` and ignore `onDone`, so a dead IPC socket leaves the rail stale
  for the rest of the session. Re-dial with the same bounded retry
  `start()` already uses once the failure is observable.
  (`lib/src/services/workspaces.dart`.)
- **NVML worker spawns without NVIDIA hardware.** `sample()` always calls
  `_nvml.read()` when no runtime-status files exist, so AMD-only systems
  dlopen NVML and keep an idle worker isolate alive for the session. Gate
  the worker on `/proc/driver/nvidia/version` or a discovered NVIDIA card.
  (`lib/src/services/gpu.dart`.)
