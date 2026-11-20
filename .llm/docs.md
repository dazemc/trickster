---
title: Trickster docs
description: Documentation index and verification rules.
---

# Trickster docs

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); the index carries no authority of its
own.

The docs site serves this file as its status page through a symlink
(`docs_site/content/status.md`). Edit and commit this `.llm/docs.md` path,
never the symlink.

## Guides

- [Overview](/) · [Installation](/installation) · [Configuration](/configuration)
- [Modules](/modules) · [Architecture](/architecture)
- [CLI reference](/cli) · [Development](/development)

## Constitution

- [AGENTS.md](https://github.com/dazemc/trickster/blob/main/AGENTS.md) — project rules
- [.llm/todo.md](https://github.com/dazemc/trickster/blob/main/.llm/todo.md) — authorized work
- [.llm/suggestions.md](https://github.com/dazemc/trickster/blob/main/.llm/suggestions.md) — open findings and proposed amendments

## Phase ledger retired

The old phase ledger is intentionally retired. It is not reconstructed here:
git history is the record of what landed, and a hand-maintained table had
already drifted from the code. Do not reintroduce phase numbers or branch
columns in this file.

## Documentation contract

- Docs never trail the code. Before merging a step, a phase, or a fix, walk
  `docs_site/content/` for claims the change invalidates; land corrections on
  `main`, one page per commit.
- Code and markdown never share a commit; two markdown files never share a
  commit.
- Build the site with `(cd docs_site && dart pub get)` once on a fresh clone,
  then `jaspr build` after edits. Do not commit generated site output.
- Performance claims carry provenance: Flutter version, output resolution,
  scale, refresh rate, build mode, scenario, and date. A single RSS snapshot is
  an observation, never a budget.
- Mark shipped behavior as current, known divergence as gap, and intent as
  aspiration. Never describe a gap in the present tense.

## Known stale site claims

These are docs gaps to correct when the relevant page is touched:

- `development.md` says packaging is planned, not published, although packaged
  releases exist and `packaging/` ships in-tree.
- Any page calling the battery UPower is stale; the current sampler is sysfs.
- Any page implying river or COSMIC workspace backends is stale; only Sway,
  Hyprland, and niri are implemented.
- Any page implying the bar follows a monitor's refresh rate, exceeds 60 fps,
  or uses per-output frame scheduling is stale.
- Any page describing the release package as blanket-stripped is stale; only
  the C++ runner is stripped.
