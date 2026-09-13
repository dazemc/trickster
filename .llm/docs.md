---
title: Trickster docs
description: Documentation index and phase progress ledger.
---

# Trickster docs

Start with the [readme](readme.md), then pick a guide. The rendered site
serves the same pages with sidebar and search.

## Guides

- [Overview](docs_site/content/index.md)
- [Installation](docs_site/content/installation.md)
- [Configuration](docs_site/content/configuration.md)
- [Modules](docs_site/content/modules.md)
- [Architecture](docs_site/content/architecture.md)
- [CLI reference](docs_site/content/cli.md)
- [Development](docs_site/content/development.md)

## Constitution

- [AGENTS.md](AGENTS.md) — project rules, module index
- [.llm/todo.md](.llm/todo.md) — work queue, in build order
- [.llm/suggestions.md](.llm/suggestions.md) — agent scratchpad

## Phase ledger

Updated on every phase merge. Status is `done`, `in progress`, or `queued`.

| Phase | Branch | Status | Headline changes |
| --- | --- | --- | --- |
| 1 — feel | `bar/phase-1` | in progress | Locale-aware clock time; locale fallback fix |
| 2 — parity | `bar/phase-2` | queued | StatusNotifier tray, MPRIS media |
| 3 — finish | `bar/phase-3` | queued | l10n, blur, fonts, per-output surfaces, tricksterctl, options, a11y |
| 4 — packaging | `bar/phase-4` | queued | Source PKGBUILD, man pages, AUR -bin path |
