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
