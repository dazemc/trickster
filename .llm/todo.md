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

## Authorized step

- M: Fall back to the settings and outputs files when the bar exits while the
  settings application is open. Add sticky `FallbackSettingsTransport` and
  `FallbackOutputsTransport` wrappers that try the socket first and flip once
  on `ControlSocketException`; keep `NativeSettingsStore`'s revision retry.
  Route load, save, document-changed reads, and outputs saves through them;
  update `usingSocket` after operations. Done when closing the fake bar after
  load still saves settings and outputs to file, later saves stay on file,
  writes are atomic, and analyze/full tests/release build are green.
