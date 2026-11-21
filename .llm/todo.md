# Trickster TODO

The work list, in build order. `AGENTS.md` is the constitution; this file is
the queue. Remove items as they land — do not check them off, do not let it
rot.

Authorized work only: the queue grants exactly the steps it lists, top-down,
and never overrides the constitution, `.llm/workflow.md`, or the domain notes
(see `AGENTS.md` → Instruction precedence).

Every step is one action with its own done-criterion. Work top-down, one step
at a time: implement it, prove it with `flutter analyze` + `flutter test`
(plus a release build when native code changes), then remove it. Never remove
an untested step; never batch multiple steps into one change.

The `.llm/` reinitialization does **not** authorize performance, refresh,
memory, or lifecycle work. Findings in `.llm/suggestions.md` remain proposals
until the user escalates them here.

Sizes: S <1 day, M 1–3 days, L 3+ days.

## Settings performance

1. **S — Settings: remote wallpaper accent.** Query the running bar's
   `status` reply and use `state.wallpaper` via `WallpaperAccentState.fromJson`
   instead of starting the settings process's wallpaper decode, cache watcher,
   thumbnailer, or grim when the state is usable. Keep the local sampler only
   as a single-flight fallback for an unreachable bar, missing state, or an
   empty state while wallpaper accent is needed. Done when tests prove local
   sampling/thumbnail/grim are never touched on a usable remote reply and the
   fallbacks still sample.

2. **S — Settings: reuse the write response.** `NativeSettingsStore.write`
   returns the written document so `_onSave` stops reading it back. Preserve
   revision-conflict handling and the serialized save queue. Done when a
   counting transport proves one write and no read-after-write, with the
   conflict tests still green.

3. **S — Settings: concurrent initial reads.** Start the settings read, outputs
   read, and native output enumeration together in `_onLoad`, then emit once.
   Preserve per-field errors and completion ordering. Done with gate-backed
   tests proving all three start before any completes.

4. **S — Settings: watch only edited documents, serialize reads.** Filter the
   config watcher to `settings.json` and `outputs.conf` (drop `.prev`/`.tmp`),
   and make `NativeSettingsStore.read` await an in-flight write. External
   revisions must still reload. Done with watcher-filter and read-after-write
   queue tests.

5. **S — Settings: scoped module drag rebuilds.** Do not emit a modules bloc
   state for pointer moves that do not change the preview slot, and read the
   last pointer outside reactive state. Done with a bloc test proving repeated
   same-slot drag previews emit once and the existing drag tests stay green.
