# Trickster repository workflow

This file interprets `AGENTS.md` (see its Instruction precedence section) and
never overrides it; on a conflict the constitution wins and this file is
corrected.

- `main` is the stable branch. Exactly one working branch, `working`, exists
  beside it and carries the code steps of the phase at the top of
  `.llm/todo.md` that still has steps. No other branches exist (no per-phase
  `bar/phase-N` branches).
- Code lands on `working`; markdown lands on `main`. `AGENTS.md`, every file
  under `.llm/`, and docs pages commit directly on `main`, immediately, one
  file per commit, and are pushed. After each markdown commit, merge `main`
  back into `working` so the tree keeps reading current docs.
- Every step is one action with one done-criterion; split work that spans
  backends, services, or widgets into separate steps. Never batch multiple
  steps into one change.
- Commit every finished TODO step as a slice: one code commit on `working`,
  then one commit per touched markdown file on `main` (switch to `main`,
  commit, push, switch back, merge `main` into `working`). A step is
  finished only when it is implemented, proven (`flutter analyze` clean,
  `flutter test` green), and removed from `.llm/todo.md`. Markdown never
  shares a commit with code or with another markdown file.
- Never start a new phase without the user's explicit go-ahead in chat: no
  branch, no first step, until asked. Merging a finished phase likewise
  waits for confirmation.
- When a phase's steps are all landed and removed, merge `main` into
  `working` first so the PR carries code only, merge `working` into `main`
  through a pull request, then reset `working` to the updated `main` for the
  next phase. The merge updates the `.llm/docs.md` phase ledger and any
  touched site pages; verify with `jaspr build`.
- Commits use the contributor's configured Git identity. Follow
  `scope: summary` in the imperative.
- Any update to `AGENTS.md` itself is committed immediately on `main`, in
  its own commit, in the same session — a constitution change never sits
  uncommitted in the tree. The same applies to every file under `.llm/`.
- Keep the tree `flutter analyze`-clean. Widget tests cover layout math,
  config parse/round-trip, settings revision retry, and module state
  mapping. Run `flutter analyze` and `flutter test` before pushing.
- Keep pub packages current. Before starting a change, run
  `flutter pub upgrade`; verify with `flutter pub outdated` that no
  resolvable package lags. Commit `pubspec.lock` (and `pubspec.yaml` when a
  constraint moves) on its own. Never `dependency_overrides` a Flutter SDK
  pin.
- After every change, review the touched code for misses (Denial parallels,
  performance traps, config warts, docs gaps) and append anything that meets
  the bar to `.llm/suggestions.md`; findings never live only in the
  transcript.
- After each phase is merged, walk every open suggestion with the user and
  settle its decision — keep, condense, move, escalate, or dismiss — before
  the next phase starts.
- Networked Git/GitHub commands (`fetch`, `push`, `gh`) run outside any
  sandbox; sandboxed credential or network failures are not authoritative.

## Graphical session control

Never log out, terminate, restart, or otherwise stop the user's local
graphical session on the user's behalf. When testing requires restarting the
bar, kill only the Trickster process — never the compositor — and wait for
explicit confirmation before touching session targets, the display manager,
reboot, or power off.

## Build

```sh
flutter analyze
flutter test
flutter run -d linux          # Wayland session with layer-shell support
flutter build linux --release # production AOT
```

A first build requires network access (pubspec + Flutter SDK); subsequent
builds reuse the cache. The runtime requires `gtk-layer-shell` and a
compositor advertising `zwlr_layer_shell_v1`.

Never force the bar onto X11 (`GDK_BACKEND=x11`): it renders as a managed
client with no exclusive zone and no anchoring, proving nothing and
misrepresenting the product. Verify visuals on native Wayland only; when the
surface cannot present, verify through the transcript or a probe and fix the
renderer instead of routing around it.
