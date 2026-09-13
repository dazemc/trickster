---
title: Configuration
description: session.conf, outputs.conf, settings.json, and live reload semantics.
---

Trickster is configured like Denial: files on disk, `KEY=VALUE` with `#` comments. The `TricksterBar` Dart API is the typed in-memory model these files decode into — not the user interface.

## Layers

### Machine environment — `/etc/trickster/session.conf`

Parsed by the Dart bootstrap at startup. Packaged template, `backup=`-preserved.

```sh
# TRICKSTER_LAYER=top
# TRICKSTER_NAMESPACE=trickster
# TRICKSTER_KEYBOARD=on_demand
# TRICKSTER_OUTPUT_CONFIG=/home/example/.config/trickster/outputs.conf
# TRICKSTER_ACCENT=#d0bcff
# TRICKSTER_LOG=trickster=info
```

| Key | Values | Default |
| --- | --- | --- |
| `TRICKSTER_LAYER` | `background`, `bottom`, `top`, `overlay` | `top` |
| `TRICKSTER_NAMESPACE` | layer-shell namespace string | `trickster` |
| `TRICKSTER_KEYBOARD` | `none`, `exclusive`, `on_demand` | `on_demand` |
| `TRICKSTER_OUTPUT_CONFIG` | path to an `outputs.conf` | XDG default |
| `TRICKSTER_ACCENT` | `#RRGGBB` machine accent override | unset |
| `TRICKSTER_LOG` | log filter | unset |

Process environment wins over the file for the same key.

### Bar placement — `~/.config/trickster/outputs.conf`

Denial's `system_bar=` grammar, verbatim. Template copied on first launch, never overwritten.

```sh
# system_bar=top,32
# system_bar=bottom,40,eDP-1
# system_bar=hidden
```

The third field and beyond select connectors; with no connectors the bar lands on every output. Thickness is clamped so a misconfigured value can never swallow an output, and it becomes the layer-shell exclusive zone.

### Settings — `~/.config/trickster/settings.json`

Versioned document with Denial's revision discipline: one async write queue, `expectedRevision` check-and-retry, current plus last-good snapshot only.

```json
{
  "revision": 1,
  "accent": "#d0bcff",
  "modules": ["workspaces", "cpu", "battery", "clock"]
}
```

## Live reload

A file watcher (200ms debounce) applies edits without restarting:

- **Hot keys** — accent, module list/order, clock format, thresholds. Providers rebuild; surfaces untouched.
- **Disruptive keys** — edge, layer, exclusive size, output set. Only the affected layer surface is destroyed and recreated.

<Warning>
An invalid file keeps the last-good state and logs the error. The bar never crashes on config.
</Warning>
