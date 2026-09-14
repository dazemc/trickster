---
title: CLI reference
description: trickster flags and the tricksterctl client.
---

## `trickster`

| Flag | Effect |
| --- | --- |
| `--check` | Preflight (wayland, configs, layer-shell, blur, outputs) and exit; non-zero on any failure |
| `--version` | Print `trickster <version>` and exit |
| `-h`, `--help` | Print usage and exit |
| `--config PATH` | Use PATH as the `outputs.conf` override for this run |
| `--edge SIDE` | One-shot `top`, `bottom`, `left`, or `right` override |

With no flags the bar starts normally. Unknown flags are a startup error, not a silent ignore.

## `tricksterctl`

A short-lived client against `$XDG_RUNTIME_DIR/trickster/control.sock`, mirroring `denialctl`:

| Command | Effect |
| --- | --- |
| `tricksterctl status` | Running state, outputs, active modules |
| `tricksterctl reload` | Re-read configs now (same path as the file watcher) |
| `tricksterctl version` | Bar and protocol versions |
| `tricksterctl --help` | Short-lived client commands and flags |

It is a control client only — never a second UI runtime.
