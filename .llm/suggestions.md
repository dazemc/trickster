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

- **Second-display live checks.** The grim fallback (18.8) and per-display
  appearance (14.12) merged without their two-output live checks, and the
  user deferred them again (no second monitor on hand). When one is
  connected, select it on the appearance page and confirm its swatches come
  from the screencopy capture and its accent overrides apply; a failure
  becomes a queued step.

- **`pickImageFile` runs a nested GTK main loop.** `my_application.cc` opens
  the chooser with `gtk_dialog_run`, so the settings process is re-entrant
  while it is open. Keep it modal and preview-free; if flicker or double-open
  reports appear, move to `GtkFileChooserNative`/portal with a callback.

- **OpenCode's usage API is experimental.** The module reads
  `$XDG_STATE_HOME/opencode/service.json` and
  `/api/experimental/usage/limits`, both internal OpenCode surfaces that may
  move between releases. If the pill silently disappears after an OpenCode
  upgrade, re-check that document and route first; the parser lives in
  `lib/src/services/opencode.dart`.

- **Three dependency majors lag their constraints.** `dbus` 0.7.15,
  `equatable` 2.1.0, and `lucide_icons_flutter` 3.1.25 are the newest
  resolvable under `pubspec.yaml`, while 0.8.0, 3.0.0, and 4.0.2 exist. A
  future step should migrate and prove each, or record why the constraint
  stays.
