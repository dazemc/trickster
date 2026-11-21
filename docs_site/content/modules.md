---
title: Modules
description: What each pill does, and how to build a new one.
---

Modules are toggled by name in `settings.json` → `modules`. A name that is not listed renders nothing and starts nothing: no subscriptions, no timers, no D-Bus names.

## Built-in modules

| Name | Pill | Source | Visibility rule |
| --- | --- | --- | --- |
| `clock` | Date caption + time; optional seconds (1 Hz while shown) and date styles; clicking opens a month calendar on an overlay | Local time, minute-aligned timer (per second with seconds shown) | Always renders |
| `cpu` | CPU caption + sparkline + percent; hover adds normalized 1/5/15-minute load averages and online core count unless disabled | `/proc/stat` plus `/proc/loadavg`/online CPU count, 1 Hz shared sampler, reused read buffers; pauses while the seat idles | Hidden if unreadable |
| `gpu` | Label + sparkline + percent per readable card | `/sys/class/drm` `gpu_busy_percent` (amdgpu) or NVML (NVIDIA, worker isolate), 1 Hz shared sampler; pauses while the seat idles | Hidden with no reading |
| `vram` | VRAM caption + sparkline + percent per GPU with dedicated memory; caption can be the queried device name | `mem_info_vram_used`/`total` (amdgpu) or NVML `nvmlDeviceGetMemoryInfo` on the same 1 Hz shared sampler; pauses while the seat idles | Hidden per GPU with no memory; AMD integrated graphics may expose a BIOS carveout as VRAM; runtime-suspended NVIDIA dGPUs do not appear |
| `ram` | RAM caption + sparkline + percent; hover adds swap used/total and percentage when published | `/proc/meminfo` (`MemTotal`/`MemAvailable`, with the `MemFree + Buffers + Cached + SReclaimable - Shmem` fallback, plus `SwapTotal`/`SwapFree`), 1 Hz sampler with a reused 8 KiB buffer; pauses while the seat idles | Hidden if unreadable |
| `temperature` | CPU/TEMP caption + Celsius + sparkline | `/sys/class/hwmon` `temp*_input`/`temp*_label`/`name`, 1 Hz; prefers `k10temp`/`coretemp`/`zenpower` with `Tctl`/`Tdie`/`Package`, otherwise the hottest readable sensor; pauses while the seat idles | Hidden when no sensor is readable |
| `disk` | DISK caption + used percent + IEC used/total/free tooltip | One configured mount path over `statvfs` in a worker isolate, 30 s; pauses while the seat idles | Hidden when the mount is missing or unreadable |
| `keyboard_layout` | KB caption + active layout; full layout set in the tooltip | Hyprland `j/devices`/`.socket2.sock`, Sway `get_inputs`/`input` events, or niri keyboard events, auto-detected; coalesced re-query and capped reconnect; no polling and no idle pause | Hidden without a Hyprland, Sway, or niri backend or a readable keyboard |
| `battery` | Gauge + percent | sysfs `power_supply`, 5 s sampler | Hidden with no `BAT*` device |
| `network` | State label (Wi-Fi, Ethernet, Connected, Linked, Disconnected, or Off) plus compact ↓/↑ rates; hover adds interface, link, Ethernet speed, and lifetime totals | One selected interface: `/sys/class/net` identity/medium, IPv4/IPv6 default routes, `/proc/net/dev` counters at 1 Hz; pauses while the seat idles; no NetworkManager/iwd metadata yet | Hidden only when no physical or pinned interface exists |
| `workspaces` | Pip rail with a deforming lens; number, dot, Roman, or browsed image pips with active, occupied, and empty states | Sway/Hyprland/niri IPC sockets, auto-detected | Always renders when listed |
| `media` | Live equalizer mark (band levels from the sink monitor; bar count configurable), now-playing text, transport keys, and the sink volume readout (level glyph, accent while muted, wheel to step, click for a slider) in full/semi/compact modes; left-click controls, right-click cycles and saves | MPRIS (`org.mpris.MediaPlayer2.*`) and the default sink (monitor and volume), event-driven | Hidden with no playing or paused player |
| `tray` | Icon per StatusNotifier item; right-click opens the D-Bus menu | StatusNotifier watcher (SNI) and `com.canonical.dbusmenu` | Hidden with no items |
| `opencode` | Terminal mark + remaining percent for the selected OpenCode Go allowance window (rolling, weekly, or monthly); the newest session's cost joins the headline, and hovering lists all three windows, reset times, and session tokens | OpenCode's local server (`$XDG_STATE_HOME/opencode/service.json` for URL and password), `/api/experimental/usage/limits` plus the newest session, 60 s poll only while configured | Hidden with no running server or no signed-in workspace |

Clicking the `opencode` pill opens the companion
[opencode-usage](https://github.com/dazemc/opencode-usage) window. When that
app is not installed, the click opens the workspace's OpenCode console URL
instead.

By default the tray leads the strip, the workspace rail is centered, and the remaining modules trail. `module_placement` moves any module between the leading, center, and trailing zones.

The settings application keeps this same zone order and lists hardware it cannot run in an Unavailable section: no battery, no dedicated GPU memory, no readable temperature sensor, a missing configured disk mount, no physical or pinned network interface, or no supported keyboard-layout backend. A running bar's control status answers keyboard availability first; the settings process environment is only the fallback. Unavailable modules stay in `settings.json` but cannot be toggled from the page. Disabled modules keep their options gear, so disk path and network interface can be configured before enabling them.

<Info>
The `ram`, `vram`, `temperature`, `disk`, `keyboard_layout`, and `network`
modules are user-requested additions. Denial has no memory, temperature, disk,
or network module, and owns keyboard input directly; do not describe these
modules as Denial parity.

`network` is kernel-only today: it never spawns `nmcli` or `iw`, and it does
not show an SSID, signal, band, or captive-portal state. Those arrive with the
NetworkManager/iwd metadata slice. Until then a Wi-Fi link uses the generic
`Wi-Fi` label, and a virtual interface can only be sampled by pinning it in
`network.interface`.

`keyboard_layout` follows the keyboard Hyprland marks `main`; Sway uses the
first keyboard that publishes layout data, falling back to the first keyboard
in compositor order, and niri follows its reported active keyboard. Other
keyboards are ignored because the bar has one global layout pill.
</Info>

`vram` renders one pill per GPU that publishes dedicated memory. It is not an
aggregate across devices, and it never fabricates a zero reading for a GPU
whose memory is unavailable.

<Info>
Tray is StatusNotifier only. Denial's XEmbed merge came from owning Xwayland, which a guest cannot borrow.
</Info>

## Building a new module

Every module follows the same three-file pattern. For a hypothetical `weather` pill:

**1. Service** (`lib/src/services/weather.dart`) — a sampler exposing a broadcast `snapshots` stream with `start()`/`dispose()`, shaped like `CpuSampler`:

```dart
class WeatherSampler {
  WeatherSampler({this.interval = const Duration(minutes: 10)});

  final Duration interval;
  final _controller = StreamController<Weather>.broadcast();

  Stream<Weather> get snapshots => _controller.stream;

  void start() {
    _sample();
    _timer = Timer.periodic(interval, (_) => _sample());
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
```

**2. Pill** (`lib/src/bar/weather.dart`) — a `StatelessWidget` taking `accent` + state, wrapped in `SystemBarCard`, text in `ShellText.systemBarValue`, and every visible string from the arb catalogs:

```dart
class WeatherPill extends StatelessWidget {
  const WeatherPill({required this.accent, required this.weather, super.key});

  final WallpaperAccent accent;
  final Weather weather;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      child: Text(
        context.l10n.weatherDegrees(weather.degrees),
        style: ShellText.systemBarValue,
      ),
    );
  }
}
```

<Warning>
No hardcoded UI text. Strings live in `lib/l10n/app_en.arb` and
`lib/l10n/app_zh.arb` and are read through `context.l10n`
(`lib/src/locale.dart`); add new keys to both catalogs. This includes
accessible labels, values, and hints.
</Warning>

**3. Wiring** — a `WeatherBloc` in `lib/src/state/weather_bloc.dart` following `CpuBloc` (explicit `Started`/`Stopped`/`Sampled` events, sampler owned by the bloc, `toJson`/`fromJson` on the state from day one), one conditional `BlocProvider` in `ModuleScope` (nothing built when the module is not listed), plus one guarded `BlocBuilder` block in `TricksterBarStrip` with a `SystemBarEntrance` wrapper and `RepaintBoundary`:

```dart
// ModuleScope: no bloc, no subscription, no timer when disabled.
if (settings.includes('weather'))
  BlocProvider<WeatherBloc>(
    create: (_) => WeatherBloc()..add(const WeatherStarted()),
  ),
```

```dart
// TricksterBarStrip: empty state hides the pill until data arrives.
if (settings.includes('weather'))
  BlocBuilder<WeatherBloc, WeatherState>(
    builder: (context, state) {
      if (state.current == null) {
        return const SizedBox.shrink();
      }
      return SystemBarEntrance(
        index: 3,
        horizontal: horizontal,
        child: Padding(
          padding: horizontal
              ? const EdgeInsets.only(right: _cardGap)
              : const EdgeInsets.only(bottom: _cardGap),
          child: RepaintBoundary(
            child: WeatherPill(accent: accent, weather: state),
          ),
        ),
      );
    },
  ),
```

Then add `'weather'` to the defaults in `settings.dart`, its copy to both arb catalogs, and a mapping test in `test/` mirroring the existing ones. The bar, theme, and config layers never change — that is the point of the seams.
