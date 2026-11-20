# Trickster repository workflow

This file interprets `AGENTS.md` (see its Instruction precedence section) and
never overrides it; on a conflict the constitution wins and this file is
corrected.

## Branches and slices

**Current.**

- `main` is the stable branch. Exactly one working branch, `working`, exists
  beside it.
- Code lands on `working`; markdown lands on `main`.
- `AGENTS.md`, every file under `.llm/`, and every docs page commit directly
  on `main`, immediately, one file per commit, and are pushed.
- After each markdown commit, merge `main` back into `working` so the tree
  keeps reading current docs and the remote stays in step.
- No per-phase branches. No second working branch.
- Never start a new phase without the user's explicit go-ahead in chat. An
  empty queue is not permission to invent work.
- When a phase's steps are all landed and removed, merge `main` into
  `working` first so the pull request carries code only; merge `working` into
  `main` through a pull request; reset `working` to the updated `main` for the
  next phase.

## Queue contract

`todo.md` grants exactly the work it lists, top-down, one step at a time.

- A step is one action with one done-criterion.
- Split work that spans backends, services, or widgets into separate steps.
- Never batch multiple steps into one change.
- Never remove an untested step.
- An empty queue means no authorized work. Propose findings in
  `suggestions.md`; do not promote them to `todo.md` yourself.
- A step is finished only when it is implemented, proven, and removed.

## Proof ladder

Every step climbs the same ladder, stopping at the first failure:

1. **Static proof.** `flutter analyze` clean and `flutter test` green.
2. **Native proof.** When C, CMake, protocols, or bundled assets change, build
   the release bundle and run it. Adding a Lucide glyph requires
   `flutter clean` before the release build so the icon font subset is rebuilt.
3. **Runtime proof.** Launch the release bar in the live Wayland session, watch
   stderr for exceptions, missing ancestors, dead pills, or lifecycle errors,
   exercise exactly what the step changed, then kill only the Trickster
   process.
4. **Visual proof.** If the done-criterion needs eyes on screen, hand the user
   the exact run-and-look commands and wait for their verdict. Never substitute
   screenshots. Never force X11 (`GDK_BACKEND=x11`): a managed toplevel has no
   exclusive zone and proves nothing.
5. **Performance proof.** Follow the protocol in `performance.md`: profile
   build for timings, release build for behavior, fixed scenario, recorded
   Flutter/output/scale/refresh, rebuild counts where relevant, RSS/PSS with
   duration, temporary instrumentation removed before commit.

A step that passes tests but errors at runtime is not done. A performance step
that cannot state its before and after is not done.

## Commit discipline

- Commits follow `scope: summary` in the imperative.
- Use the contributor's configured Git identity.
- Code changes are one commit on `working`. Markdown never shares a commit
  with code or with another markdown file.
- A finished step lands as one code commit on `working`, then one commit per
  touched markdown file on `main` (switch, commit, push, switch back, merge).
- Any change to `AGENTS.md` or `.llm/` commits immediately on `main` in its own
  commit in the same session.
- `pubspec.lock` changes commit on their own; move `pubspec.yaml` only when a
  constraint actually moves. Never add a `dependency_overrides` entry for a
  Flutter SDK pin.
- Before starting work, run `flutter pub upgrade`; verify with
  `flutter pub outdated` that no resolvable package lags.

## Build environment

```sh
flutter analyze
flutter test
flutter run -d linux          # Wayland session with layer-shell support
flutter build linux --release # production AOT
```

- A first build needs network access for pubspec and the Flutter SDK; later
  builds reuse the cache.
- On a fresh clone, run `(cd docs_site && dart pub get)` before
  `flutter analyze`, or unfetched site dependencies appear as analyzer errors.
- The runtime needs `gtk-layer-shell` and a compositor advertising
  `zwlr_layer_shell_v1`.
- `trickster --check` is the install preflight; it is strict about config and
  reports layer-shell, blur capability, idle-notify, and outputs.
- Release builds tree-shake the Lucide icon font. A new glyph without a clean
  can reuse the previous subset and ship blank. Fresh checkouts are unaffected.
- `l10n.yaml`'s quoted header is load-bearing. Flutter 3.50's `gen-l10n` emits
  deprecated `GlobalMaterialLocalizations` infos from generated files; the
  quoted `header: "// ignore_for_file: deprecated_member_use"` suppresses them.
  Removing or unquoting it breaks `flutter analyze`.
- The docs site is a separate Jaspr project. Build it with `jaspr build` from
  `docs_site/`; its output is not committed.
- Production logs are state changes and errors only. Debug/profile transcripts
  are evidence; release silence is the product.

## Review loop

After every change, review the touched code for Denial parallels, performance
traps, memory retention, lifecycle misses, configuration warts, and docs gaps.
Append only findings that meet the bar to `suggestions.md`; findings never live
only in the transcript. Remove an entry in the same change that resolves it.

At a phase boundary, walk every open suggestion with the user and settle its
decision — keep, condense, move, escalate, or dismiss — before the next phase
starts. Silence is a valid review outcome; do not add noise to justify the
read.

## Graphical session control

Never log out, terminate, restart, or otherwise stop the user's local
graphical session on the user's behalf. When testing requires restarting the
bar, kill only the Trickster process — never the compositor — and wait for
explicit confirmation before touching session targets, the display manager,
reboot, or power off.
