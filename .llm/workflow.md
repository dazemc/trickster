# Trickster repository workflow

- `main` is the stable branch. Each TODO phase gets its own branch from
  `main`: `bar/phase-1`, `bar/phase-2`, `bar/phase-3`, `bar/phase-4`,
  `bar/phase-5`.
  All of the phase's steps land on that branch — never on `main`, never on
  another phase's branch.
- Commit every finished TODO step on the phase branch as a slice: one commit
  for the code, then one commit per touched LLM-maintained markdown file
  (`.llm/todo.md`, `.llm/suggestions.md`, docs). A step is finished only when
  it is implemented, proven (`flutter analyze` clean, `flutter test` green),
  and removed from `.llm/todo.md`. No direct pushes to `main` beyond initial
  scaffolding.
- Never start a new phase without the user's explicit go-ahead in chat: no
  branch, no first step, until asked. Merging a finished phase likewise
  waits for confirmation.
- When a phase's steps are all landed and removed, merge the phase branch
  back into `main` through a pull request, then branch the next phase fresh
  from the updated `main`. The merge updates the `.llm/docs.md` phase ledger
  and any touched site pages; verify with `jaspr build`.
- Commits use the contributor's configured Git identity. Follow
  `scope: summary` in the imperative.
- Any update to `AGENTS.md` itself is committed immediately, in its own
  commit, in the same session — a constitution change never sits uncommitted
  in the tree. The same applies to every file under `.llm/`: one file per
  commit, committed in the same session as the edit, never bundled with
  code or with each other.
- Keep the tree `flutter analyze`-clean. Widget tests cover layout math,
  config parse/round-trip, settings revision retry, and module state
  mapping. Run `flutter analyze` and `flutter test` before pushing.
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
