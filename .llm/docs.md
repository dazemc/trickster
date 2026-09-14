---
title: Trickster docs
description: Documentation index and phase progress ledger.
---

# Trickster docs

Domain knowledge subordinate to `AGENTS.md` and `.llm/workflow.md` (see
`AGENTS.md` → Instruction precedence); the index and phase ledger carry no
authority of their own.

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
- [.llm/suggestions.md](.llm/suggestions.md) — user-reviewed suggestions

## Phase ledger

Updated on every phase merge. Status is `done`, `in progress`, or `queued`.

| Phase | Branch | Status | Headline changes |
| --- | --- | --- | --- |
| 1 — Bloc migration | `working` | done | flutter_bloc cutover, toJson states, observer transcript |
| 2 — feel | `working` | done | Workspace pip rail (lens, states, focus verbs, reconnect); CPU/GPU meters (sysfs + NVML, gated); battery bolt and tap; locale clock |
| 3 — parity | `working` | done | StatusNotifier tray with menus and icon lookup, MPRIS media, menus on transient overlay surfaces |
| 4 — finish | `working` | done | l10n (en/zh), blur, fonts, per-output surfaces and hotplug, tricksterctl control socket, typed options, accessibility, tooltips |
| 5 — packaging | `working` | done | Source PKGBUILD, man pages, AUR -bin recipe, v0.1.0 release asset |
| 6 — follow-ups | `working` | done | Direct and SVG tray icon sources, single `--check` implementation |
| 7 — version sync | `working` | done | One test pinning every version field to `Cli.appVersion` |
| 8 — settings application | `working` | done | Same binary in settings mode: transport, appearance, modules, displays (live edge/thickness), options, language, about; vertical compact pills and pill tooltips; 0.2.0 release |
| 9 — parity and release hygiene | `working` | done | Docs reality pass, Denial porting pin, wallpaper accent sampler (candidate palette, click-to-copy hex), AUR recipe kept in tree, tag-driven release workflow with package/pin automation |
| 10 — docs and install hygiene | `working` | done | Docs-site analyzer boundary documented, AUR install path, manual release runbook, AUR publishing automated in the release workflow |
