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

- **The module guide predates the arb pipeline.** `docs_site/content/modules.md`
  still builds a pill with raw strings and never mentions
  `lib/l10n/app_en.arb`, so a module added from the guide would
  reintroduce hardcoded UI text. Update the guide and
  `docs_site/content/development.md` when 4.2 lands.
- **`--check` has two implementations; the Dart one is dead.** The native
  runner (`linux/runner/my_application.cc` -> `run_check`) intercepts
  `--check` before the Dart entrypoint starts, so `lib/main.dart`'s `_check`
  never runs and can drift from the reported diagnostics. Delete the Dart
  path or route the native flag through Dart.
- **Tray icon lookup is theme-name only.** Items publishing an absolute file
  path or a `file://` URI in `IconName`, and items whose only asset is SVG,
  keep the placeholder; Denial resolved both. Add the direct-path arm and an
  SVG rasterizer only if a real item needs them
  (`lib/src/services/status_notifier.dart`).

