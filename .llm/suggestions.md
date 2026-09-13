# Trickster suggestions

Agent-proposed, user-reviewed suggestions. If you see something the queue,
the constitution, or the code gets wrong — a missed Denial parallel, a
performance trap, a config wart, a docs gap — propose it here so the next
session sees it. Standing rules and instructions belong in `AGENTS.md`, not
here.

Non-authoritative: entries inform decisions but bind nothing until the user
escalates them to `.llm/todo.md` (see `AGENTS.md` → Instruction precedence).

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

- **MPRIS's first `PropertiesChanged` can beat the match rule.** The `dbus`
  package installs signal matches without awaiting the bus round-trip, so a
  change emitted between player discovery and match installation is lost
  until a topology event or the one-minute recovery scan (Denial shares the
  window; `test/mpris_test.dart` re-emits to stay deterministic). A short
  post-selection refresh would close it if the media pill feels stale.
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
- **Tray icons resolve only from pixmaps.** Items that publish `IconName` /
  `IconThemePath` without an `IconPixmap` render the placeholder square;
  freedesktop icon-theme lookup is not ported (Denial resolved it on a
  worker). Add resolution or accept the placeholder before tray parity is
  called done. (`lib/src/bar/tray.dart`.)
- **Tray tooltips are semantics-only.** A Material `Tooltip` overlay clips to
  the 32px layer surface, so hover text was left to semantics. The 3.5 menu
  surfaces are the template: a transient overlay view per popup.
  (`lib/src/bar/tray.dart`, `lib/src/bar/tray_menu.dart`.)
- **Menu surface placement is Hyprland-shaped.** `trickster_menu_surface_new`
  anchors opposite the strip and sizes to the monitor because Hyprland places
  layer surfaces inside the area left by other surfaces' exclusive zones; a
  compositor that positions them differently leaves the bar band uncovered and
  clicks there cannot dismiss. Re-verify menu placement on Sway, niri, river.
