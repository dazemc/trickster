# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criteria. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Phase 1 — Bloc migration

Riverpod → `flutter_bloc`, explicit events and states, no Cubits. Every
state class ships `toJson`/`fromJson` from day one (convention only, no
HydratedBloc) so `tricksterctl status` and agent runtime review read real
state later. Debug/profile builds run a verbose `BlocObserver`
(transitions + create/close + errors + timing) to stderr; release stays
silent per the logging rules.

## Phase 2 — feel (behaves like Denial)

## Phase 3 — parity (absent modules)

## Phase 4 — finish


## Phase 5 — packaging and release


## Phase 6 — follow-ups


## Phase 7 — version sync


## Phase 9 — parity and release hygiene

## Phase 8 — settings application (Denial parity)

The bar stopped at "no settings window in v1"; the user replaced that with
a settings application: the same binary run in settings mode
(`trickster-settings`), its own process and engine with no strip surfaces,
writing through the running bar's control socket (file transport as
fallback) and covering exactly the settings the bar has. The version stays
0.1.0 until the user calls a bump.

## Phase 10 — docs and install hygiene (proposed)

Proposed by the agent after the Phase 9 walk; implementation waits for the
user's explicit go-ahead, step by step as always.

- **10.1 (S) Give the docs site a stable analyzer boundary.** A fresh clone
  that runs only the root `flutter pub get` fails `flutter analyze` with
  ~72 errors from the separate Jasper site under `docs_site/`. Reproduce on
  a clean checkout, then document the site's own `dart pub get` in its
  development page and wherever the repo tells contributors to analyze;
  done when a fresh clone following the written steps analyzes clean.
- **10.2 (S) Document the AUR install path.** `docs_site/content/installation.md`
  never mentions `trickster-bin`; add the `yay -S trickster-bin` section
  (0.2.0, manual maintenance) and drop the "planned" framing if any
  remains; done when the page matches the published recipe.
- **10.3 (S) Write the manual release runbook.** `development.md` describes
  the tag workflow but not the human steps that follow it (refresh the pin,
  clone AUR, push to `master` — the branch is `master`, not `main`). Add
  the runbook; done when the documented steps reproduce the 0.2.0 publish
  without prior session knowledge.
- **10.4 (M) Publish to the AUR from the release workflow.** The pin job
  stops at the in-repo commit; add a final job that pushes the refreshed
  recipe to `aur.archlinux.org/trickster-bin` (`master`) through a deploy
  key secret, guarded like the release job (tags only, never dry runs).
  Depends on the user provisioning the key. Done when a tag run publishes
  the recipe and a fresh AUR clone matches the release asset.
