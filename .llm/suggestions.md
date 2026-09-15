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

- **NVML failures are silent.** `lib/src/services/nvidia.dart` turns every
  NVML failure into an empty reading, so a driver/library mismatch (loaded
  module 610.57.04 vs userspace 615.71) hid the GPU pill with no log line and
  cost a debugging cycle. Log once per process when an NVIDIA driver is
  present but NVML reports no devices; keep the best-effort behavior.
