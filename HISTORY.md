# Trickster history

Human-readable changelog of what was asked and what was done, newest last.

Agents: this file is append-only — follow the entry scheme in `AGENTS.md`
without loading this file. Never read it for context.

## Entries

<!-- append new entries below this line -->
### 2026-09-12 — Create HISTORY.md
- USER_PROMPT: create a HISTORY.md that will not be read by llm models so keep it out of .llm, update AGENTS.md with instructions to update this file, keep it in the root dir, follow the scheme USER_PROMPT -> AGENT_INTERPRETATION -> COMMIT_LINK, start now with this prompt.
- AGENT_INTERPRETATION: root HISTORY.md as an append-only human changelog agents never load (format lives in AGENTS.md, anchored appends need no read); AGENTS.md gains the per-step append rule; first entry is this prompt.
- COMMIT: 49f982f e1aca59
### 2026-09-12 — Land shared action card (2.2)
- USER_PROMPT: continue this project; execute the next phase; work the queue top-down.
- AGENT_INTERPRETATION: implemented TricksterActionCard (Semantics button, tap, hover/focus highlight, accent ring) mirroring Denial's _BatteryActionCard; focus callback needs a double pump in widget tests (async delivery behind the full tree), documented in-tree; proven analyze-clean, 28/28 green, 5s clean runtime.
- COMMIT: 9fb16b8 00a4a23
### 2026-09-12 — Land config blocs (1.1)
- USER_PROMPT: execute the next phase (Bloc migration first).
- AGENT_INTERPRETATION: added flutter_bloc/bloc_test plus Settings/Session/Outputs blocs with explicit events and toJson/fromJson states from day one; added fromJson to all three config models; bloc_test event→state plus JSON round-trips; Riverpod untouched; proven analyze-clean, 35/35 green, clean 5s runtime.
- COMMIT: b9aafe4 f6ff7d2
### 2026-09-12 — Land module blocs (1.2)
- USER_PROMPT: continue (execute Phase 1 Bloc migration).
- AGENT_INTERPRETATION: added Cpu/Battery/Workspaces/Clock blocs with Started/Stopped/sample events, sampler subscription owned by each bloc and cancelled on close, fake-sampler subclasses for tests, JSON shapes on all service models, bloc_test lifecycle/sequencing plus round-trips; proven analyze-clean, 44/44 green, clean 5s runtime.
- COMMIT: b45c4ad 1f2fe2b
### 2026-09-12 — Equatable across bloc events and states
- USER_PROMPT: use the equatable library in bloc, before any other phase.
- AGENT_INTERPRETATION: added equatable dep; all bloc events and states extend Equatable with props (spread trick for list fields, documented in-tree); new WorkspacesState wrapper so the list state has value semantics and a JSON shape; tests assert direct equality on distinct instances; narrowed the equality suggestion to the remaining _apply guard. Proven analyze-clean, 44/44 green.
- COMMIT: fa39079 6134c4d
