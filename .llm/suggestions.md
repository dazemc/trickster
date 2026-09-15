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

- **Per-display appearance still needs a two-output check.** 14.12 is merged,
  but the live check (two outputs holding different accent picks) never ran —
  no second monitor was available. Verify on a second display when one is
  connected; a failure becomes a new queued step.
- **`appearance.blur` does not gate the settings window.** The bar forces
  opaque pills when the key is off, while `lib/src/settings/app.dart` keys
  translucency only on the host capability, so turning blur off still leaves
  the window glass. Decide whether the key should gate both processes; the
  change is one `&&` in the settings root.
- **Workspace-name pip mappings detach silently.** `image_by_workspace` keys
  on the workspace name, so a rename or a renumbered dynamic workspace drops
  its artwork without any signal. Either surface detached keys in the mapping
  editor or accept it as the documented behavior; ids are no more stable.
- **`pickImageFile` runs a nested GTK main loop.** `my_application.cc` opens
  the chooser with `gtk_dialog_run`, so the settings process is re-entrant
  while it is open. Keep it modal and preview-free; if flicker or double-open
  reports appear, move to `GtkFileChooserNative`/portal with a callback.
- **Widget-test contract misses the single-pump rule.** Pumping
  `pumpBarHarness` twice in one test reuses the providers and their blocs, so
  a second `settings:` argument is silently ignored (the meter-sparkline test
  had to split in two). Add a bullet to the contract in
  `docs_site/content/development.md`: one harness pump per test.
- **Tray SVG scaling has no regression test.** The corner-cropping fix in
  `status_notifier.dart` mirrors the pip-artwork fix, but only
  `test/pip_artwork_test.dart` pins the behavior. Extend
  `decodeStatusNotifierIconForTesting` coverage with the same corner-pixel
  assertion before the tray decode path changes again.
