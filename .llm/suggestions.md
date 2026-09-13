# Trickster suggestions

A scratchpad for any LLM agent working this repo. If you see something the
queue, the constitution, or the code gets wrong — a missed Denial parallel,
a performance trap, a config wart, a docs gap — write it here so the next
session sees it.

## Rules

- Entries must be **absolutely needed**: they prevent a future mistake,
  unblock queued work, or record a decision with its reason. Brainstorming,
  nice-to-haves, and restatements of `.llm/todo.md` do not belong here.
- One entry per issue. Keep it to five lines: what, where, why, and what
  to do about it.
- Remove an entry in the same change that resolves it — same discipline as
  `.llm/todo.md`.
- After finishing any `.llm/todo.md` step, re-read this file and update it, but
  only if something meets the bar above. No obligatory edits. Silence is a
  valid review outcome.

## Open suggestions

- **Never run the bar on X11.** Forcing `GDK_BACKEND=x11` renders, but the window tiles as a managed client with no exclusive zone and no anchoring — it proves nothing about the product and misrepresents it. Verify visuals on native Wayland only (transcript/probe when the surface can't present); fix the renderer instead of routing around it. (Standing user instruction.)
- **Ask the user for on-screen verification.** Screenshot spelunking burns whole sessions locating pill pixels and still can't judge styling. When a step's done-criteria needs eyes (lit states, layout, motion), hand the user the exact run-and-look commands and wait for their verdict instead. (Standing user instruction from 1.8.)
- **Hyprland blocks its main loop on fresh `.socket.sock` connections.** `hyprCtlFDTick` accepts one, then `poll(..., 5000)`s until the command arrives; a client that connects on the UI isolate and flushes the write a turn later deadlocks the session if the platform thread enters a compositor wait first — the initial configure lands at gtk-layer-shell's map timeout and the surface is torn down. Keep `j/*` queries connect+write-adjacent (worker isolate in `workspaces.dart`) and finish the layer handshake before the engine starts (`my_application.cc`). (Root cause of the "no frames" startup failure.)
- **FakeAsync deadlocks on the bloc event loop.** In widget tests, `await pumpEventQueue()` after `bloc.add()` and `await bloc.close()` both hang forever — bloc's internal pipeline needs real event-loop turns that FakeAsync never gives unprompted. Seed states via constructors, let `BlocProvider(create:)` own lifecycle (its unawaited close is safe), never await close in a widget test. (`test/widget_test.dart` documents both.) `Bloc.close()` awaits event-drain before `super.close()`/`onClose`, so `bloc-` lines for event-blocs never appear under FakeAsync either — assert disposal via a close-invocation flag on an injected subclass, not the transcript. (`test/gating_test.dart`.)
- **Guard `_apply` against no-op reloads.** Models now have value equality, but every watcher fire still writes all providers unconditionally — including self-fires once anything writes `settings.json`. Skip the write (and the sampler restarts) when nothing changed, before 4.11/4.12 and tricksterctl. (`lib/src/app.dart`.)
- **First frame renders defaults, not config.** `_apply(widget.initial)` runs post-frame, so frame one always shows default top/32/all-modules before the real config lands. Seed the providers synchronously or accept the flash explicitly. (`lib/src/app.dart`.)
- **Directionality is hardcoded ltr.** RTL locales will mirror nothing until this follows the resolved locale. Fix inside C1, not after — otherwise every golden-free layout test written before then bakes in ltr. (`lib/src/app.dart`.)

