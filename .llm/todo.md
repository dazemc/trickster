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

## Network module

- **M — Add the network module kernel slice.** Add `NetworkSample`,
  `/sys/class/net` interface discovery with physical/tunnel filtering,
  IPv4/IPv6 default-route selection, a 1 Hz `/proc/net/dev` sampler with
  measured-elapsed rates and reset semantics, the `NetworkBloc`, the text
  `network` pill, `NetworkOptions` (`interface`, `show_rates`),
  ModuleScope/gating/status/settings/l10n wiring, and tests. Default-on after
  battery. No NetworkManager/iwd metadata, no D-Bus, no process spawns.
  Done: parser/selection/symlink/tunnel tests, sampler rate/reset/pause/resume
  tests, bloc/pill/config/gating/widget/status/l10n tests, `flutter analyze`,
  full `flutter test`, and a release build pass; headless status proves the
  live host interface without restarting the bar.
