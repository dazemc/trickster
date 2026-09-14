<h1 align="center">Trickster</h1>

<p align="center"><strong>A Flutter-native Wayland status bar.</strong></p>

Denial owns the desktop. Trickster just visits.

It takes Denial's system bar — the floating pills, the accent, the motion —
and runs it as a guest on other people's compositors: one thin layer-shell
strip per display, no compositor attached. A doll carrying Denia's likeness
into other worlds.

## How it works

Trickster is an ordinary Wayland client. It speaks `zwlr_layer_shell_v1`
through `gtk-layer-shell`, asks the host for a strip of screen, and paints
Dart there. The Dart side runs AOT-compiled, same as any Flutter release
build.

The split of duties is simple:

- The host compositor (Sway, Hyprland, niri, river, COSMIC) owns everything
  real: outputs, input, buffers, presentation.
- Trickster owns everything visible: strip layout, pill cards, modules,
  accent, motion, and which regions take clicks.

One surface per connected output. Each output's exclusive zone reserves
exactly what the pills occupy — nothing more.

```text
Host compositor ──> layer-shell strip ──> Flutter scene (one surface per output)
          input <──── interactivity modes <──── pill hit regions <────┘
                                                                   │
Displays <────────────── host composition <────────────── client buffers
```

### Small by discipline

The strip is tiny, but waste is still forbidden. One engine, one UI isolate,
one process; blocking OS work runs on worker isolates that host no widgets.
A module you turn off holds no subscriptions, no timers, no D-Bus names. Updates arrive over D-Bus signals and compositor IPC — nothing
polls on a timer when the platform can push instead. Each pill repaints only
when its own data changes, and surfaces for unplugged outputs are destroyed
on the spot.

## Modules

The Denial set, in Denial's visual language:

- Clock, battery (UPower), media (MPRIS), system tray (StatusNotifier),
  CPU/GPU, workspaces (Sway, Hyprland, and niri backends).
- Backdrop blur where the host offers `ext-background-effect`; a clean
  translucent fill everywhere else. Trickster never fakes blur.
- Tray is StatusNotifier only — Denial's XEmbed support came from owning
  Xwayland, which a guest can't borrow.

## Configuration

Files on disk, Denial-style `KEY=VALUE` with `#` comments:

- `/etc/trickster/session.conf` (`TRICKSTER_*`): machine environment —
  config-path override, layer, namespace, keyboard behavior, accent
  override, log filter.
- `$XDG_CONFIG_HOME/trickster/outputs.conf`: bar placement using Denial's
  `system_bar=` grammar (`top,32`; `bottom,40,eDP-1`; `hidden`).
- `$XDG_CONFIG_HOME/trickster/settings.json`: versioned settings document
  with Denial's revision discipline.
- `trickster --check` validates the install and protocols without starting
  the bar. `tricksterctl status` asks the running bar how it feels.

Edits apply live: looks rebuild immediately, while edge, layer, and output
changes recreate just the affected surface. A broken file keeps the last
good state and logs a complaint; the bar itself never goes down over config.

## Why Trickster

**Trickster** is Denia's doll from *Wuthering Waves* — small, carried into
other worlds, unmistakably hers anyway.

## Project status

Early development. Modules, config schema, and the control protocol can all
still change before 1.0.

## Supported compositors

| Compositor | Working | Binaries available |
| --- | :---: | :---: |
| Sway | 🔲 | ❌ |
| Hyprland | 🔲 | ❌ |
| niri | 🔲 | ❌ |
| river | 🔲 | ❌ |
| COSMIC | 🔲 | ❌ |

Everything above speaks `wlr-layer-shell`. KDE Plasma and GNOME Mutter are
out of scope for v1 — their layer-shell support is uneven, and fallbacks
don't exist yet.

## Install

Build from source with Flutter's Linux desktop support:

```sh
flutter build linux --release
```

At runtime it needs `gtk-layer-shell` and a compositor advertising
`zwlr_layer_shell_v1`. Packaged releases are published on
[GitHub](https://github.com/dazemc/trickster/releases); the Arch and AUR
recipes ship in-tree under `packaging/`.

Smoke-test without starting anything:

```sh
trickster --check
```

## Documentation

Full docs live in [`docs_site/content/`](docs_site/content/) and render as a
static site via [Jaspr Content](https://docs.jaspr.site/content):

- [Overview](docs_site/content/index.md)
- [Installation](docs_site/content/installation.md)
- [Configuration](docs_site/content/configuration.md)
- [Modules](docs_site/content/modules.md)
- [Architecture](docs_site/content/architecture.md)
- [CLI reference](docs_site/content/cli.md)
- [Development](docs_site/content/development.md)

Build the site with `jaspr build` inside `docs_site/`. Project rules live in
[AGENTS.md](AGENTS.md).

## License

GPL-3.0-or-later for Trickster's original code. Anything ported from Denial
keeps its origin and attribution; third-party pieces keep theirs.
