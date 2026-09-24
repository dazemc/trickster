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

- [Overview](/) · [Installation](/installation) · [Configuration](/configuration)
- [Modules](/modules) · [Architecture](/architecture)
- [CLI reference](/cli) · [Development](/development)

## Constitution

- [AGENTS.md](https://github.com/dazemc/trickster/blob/main/AGENTS.md) — project rules, module index
- [.llm/todo.md](https://github.com/dazemc/trickster/blob/main/.llm/todo.md) — work queue, in build order
- [.llm/suggestions.md](https://github.com/dazemc/trickster/blob/main/.llm/suggestions.md) — user-reviewed suggestions

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
| 11 — workspace rail parity | `working` | done | Centered numbered rail (Denial's indicator slot), state-styled numbers with a deforming lens, fixed workspace count on every monitor (`workspaces.workspace_count`) |
| 12 — pill glass | `working` | done | Pill-region backdrop blur (scanline-rounded `wl_region`), Denial's dark-glass backing with a painted rim sheen |
| 13 — bar zones and placement | `working` | done | Tray pinned to the leading edge (Denial layout), per-module `module_placement` zones, Position selector in the settings application |
| 14 — settings depth | `working` | in progress | Lucide icons for every glyph; per-option reset arrows on module options (steps 1-3 landed) |
| 15 — docs site delivery | `main` | done | Trickster mark favicon and logo, GitHub Pages workflow at dazemc.github.io/trickster |
| 16 — workspace rail from the compositor | `working` | done | Rail mirrors compositor placement; chain settings retired |
| 17 — workspace pip styles | `working` | done | Number/dot/Roman/image pips, per-workspace artwork with own colors, SVG recolor, uniform numeral scaling |
| 18 — bar options and layout | `working` | done | Zones clamp and wrap with an auto-growing strip; meter parity, custom prefixes, GPU thresholds, wheel-picked colors; clock seconds and date styles; media modes with equalizer and right-click cycling; grim screencopy sampling; drop targets and unavailable rows |
| 20 — bloc-only state | `working` | done | Settings document, wallpaper accent, modules page, tray and tooltip hosts on blocs; `ChangeNotifier`/`Cubit` guard test |
