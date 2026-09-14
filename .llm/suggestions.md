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

## Open suggestions

- **Docs still say the release and client are planned.** `README.md`,
  `docs_site/content/{cli,architecture,installation}.md` call `tricksterctl`
  and the packages "planned"/"not published" while 0.2.0 is released and the
  AUR recipe is verified. Update the wording so readers don't rebuild what
  exists.
- **The wallpaper accent sampler was never implemented.** `resolveAccent`
  only reads `accent`/`TRICKSTER_ACCENT`; Denial derives the accent from the
  wallpaper, and `.llm/porting.md` lists "configured color plus optional
  local sampler" as the honest replacement. Add an opt-in, bounded sampler
  (downscaled working buffer, freed after commit).
- **The Denial porting reference is not pinned.** `.llm/porting.md` tells
  future sessions to port from `dart_shell`, but no revision/tag of the
  local Denial checkout is recorded, so ports can drift against a different
  tree. Record the revision used and where the checkout is expected.
- **AUR submission is unresolved.** `packaging/aur/trickster-bin` is built
  and pinned but not published to aur.archlinux.org; the recipe says nothing
  about intent. Decide (needs the user's AUR account) and record the
  decision so the docs stop hedging.
- **Releases are hand-assembled.** The 0.1.0 and 0.2.0 loop (makepkg → hash
  → AUR pin → gh release → verify) is manual and one wrong hash breaks the
  AUR recipe; a tag-triggered workflow could build, hash, and attach the
  asset, updating the pin from the built artifact.
