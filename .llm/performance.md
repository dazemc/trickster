# Trickster performance and memory

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); on a conflict the higher document wins
and this file is corrected.

## Performance

The strip is small. Waste is still forbidden. Treat idle CPU and frame cost
as first-class bugs.

- Production builds are AOT release. Do not ship JIT, profile, or
  debug-engine artifacts in packages.
- One Flutter engine, one UI isolate, one process — per process. Blocking
  OS work that must never stall the frame loop (Hyprland IPC, NVML) may run
  on worker isolates; they host no widgets and no second engine.
  `tricksterctl` is a short client against the control socket, never a
  second UI runtime. The settings application hosts its own engine only
  while it is open; it never hosts the bar.
- Do not start a module that is not configured. Disabled modules have zero
  subscriptions, zero timers, zero D-Bus names.
- Rebuild only the module whose data changed. Use bloc `select`,
  `RepaintBoundary` around each pill, and a clock that ticks inside its own
  widget — never rebuild the strip on a 1 Hz clock.
- Prefer D-Bus signals and compositor IPC events over polling. `/proc` and
  sysfs samples are bounded (CPU/GPU at 1 Hz, shared across cards). Reuse
  read buffers; do not allocate a new string per sample if a reused buffer
  will do.
- Workspace backends are event-driven sockets (Sway/i3 IPC, Hyprland,
  niri). No interval polls when the compositor can push.
- Exclusive zone equals the laid-out strip. Do not reserve more than the
  pills occupy. Destroy surfaces for disconnected outputs immediately.
- Frame scheduling follows the output that hosts the surface. Do not run
  vsync work for outputs that have no bar.
- Backdrop blur, shadows, and clips are opt-in and host-dependent. Default
  path is fill + border, matching Denial's pills when blur is unavailable.
- Log in production only on state changes and errors. No per-frame or
  per-sample logging.

### Hyprland IPC contract

Hyprland services `.socket.sock` (commands) and `.socket2.sock` (events) on
its main loop. A client that connects without writing immediately makes the
compositor block in `poll()` waiting for the command, which can stall the
initial layer-shell configure and tear the first surface down. Therefore:

- A request connection is dialed and written **in one turn**. Never hold an
  idle `.socket.sock` connection between commands. Event subscriptions use
  `.socket2.sock`, which is meant to stay open.
- Every request is a one-shot connection with a bounded read: return as soon
  as the accumulated bytes parse as a complete JSON document (or the reply
  is `ok`/`error:`), cap the reply bytes, time out, and close. Some Hyprland
  versions keep the connection open after the reply.
- A refused or reset connection (compositor restarting) is retried once on a
  fresh connection after a short settle delay; event sockets reconnect with
  capped backoff.
- Socket work runs on worker isolates (`Isolate.run`), so neither a blocking
  dialect nor a reconnecting event socket can stall the frame loop.
- The engine starts only after the first strip surface has completed its
  layer-shell initial configure (`trickster_surface_new` in
  `linux/runner/my_application.cc`), so the first Dart IPC request cannot
  race the handshake.

Implementations: `lib/src/services/workspaces.dart` (`HyprlandWorkspaces`),
native handshake comment in `linux/runner/my_application.cc`.

## Memory

Resident size should look like a bar, not like a Flutter gallery.

- Dispose every D-Bus connection, stream subscription, file watcher, IPC
  socket, and `LayershellWindowController` in the same scope that created
  it. Leaks in those objects are release blockers.
- Cache tray pixmaps and decoded images at display size with a hard cap and
  eviction. Do not retain raw D-Bus byte arrays after decode.
- Do not copy Denial's entire `dart_shell`. Port only the bar, theme,
  tokens, motion, and the compositor-agnostic services those modules need.
- No Material `Icons` font if a smaller subset or Denial's existing font
  stack covers the glyphs. Bundle only fonts and assets the bar paints.
  Measured: two full JetBrains Mono weights (Medium 500, Bold 700) add
  551,688 bytes to the release bundle; a glyph subset was rejected because
  tray, media, and workspace text is dynamic. Pills render with an empty
  fontconfig.
- Settings documents: current + last-good only. Config parse trees are
  discarded after they become the typed model.
- Release packages are stripped. `options=('!strip')` is not the default
  here; Denial retains symbols because it is a compositor. A bar does not
  get that exception without a measured reason.
- Never hold previous frames, screenshot bitmaps, or offscreen copies of
  the host wallpaper unless a measured accent sampler is enabled — and then
  only a downscaled working buffer, freed after the accent is committed.
