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

- **AUR publishing is paused by the user's call, and the published recipe
  is stale.** aur.archlinux.org/trickster-bin HEAD (`e70aa23`) is titled
  "Initial import: trickster-bin 0.2.0-1" but its PKGBUILD is the 0.1.0
  recipe (hash `f1097607…`); the 0.2.0 recipe with hash `875ed281…` sits
  ready in `packaging/aur/trickster-bin`. AUR users still install 0.1.0.
  Do not push the correction without an explicit go-ahead, and add the AUR
  link to `docs_site/content/installation.md` when publishing resumes.

- **Root `flutter analyze` needs `docs_site` dependencies.** The docs site is
  a separate Jaspr project; a fresh clone that only runs the root
  `flutter pub get` sees ~72 errors from `docs_site/**` until its own
  `dart pub get` runs. The release workflow now scopes analysis to
  `lib bin test`; either document the site's pub get in
  `docs_site/content/development.md` or give the site its own analyzer
  boundary.
