---
title: Modules
description: What each pill does, and how to build a new one.
---

Modules are toggled by name in `settings.json` → `modules`. A name that is not listed renders nothing and starts nothing: no subscriptions, no timers, no D-Bus names.

## Built-in modules

| Name | Pill | Source | Visibility rule |
| --- | --- | --- | --- |
| `clock` | Date caption + time; optional seconds (1 Hz while shown) and date styles | Local time, minute-aligned timer (per second with seconds shown) | Always renders |
| `cpu` | CPU caption + sparkline + percent | `/proc/stat`, 1 Hz shared sampler, reused read buffer | Hidden if unreadable |
| `gpu` | Label + sparkline + percent per readable card | `/sys/class/drm` `gpu_busy_percent` (amdgpu) or NVML (NVIDIA, worker isolate), 1 Hz shared sampler | Hidden with no reading |
| `battery` | Gauge + percent | sysfs `power_supply`, 5 s sampler | Hidden with no `BAT*` device |
| `workspaces` | Pip rail with a deforming lens; number, dot, Roman, or browsed image pips with active, occupied, and empty states | Sway/Hyprland/niri IPC sockets, auto-detected | Always renders when listed |
| `media` | Equalizer mark, now-playing text, and transport keys in full/semi/compact modes; left-click controls, right-click cycles | MPRIS (`org.mpris.MediaPlayer2.*`), event-driven properties | Hidden with no playing or paused player |
| `tray` | Icon per StatusNotifier item; right-click opens the D-Bus menu | StatusNotifier watcher (SNI) and `com.canonical.dbusmenu` | Hidden with no items |

By default the tray leads the strip, the workspace rail is centered, and the remaining modules trail. `module_placement` moves any module between the leading, center, and trailing zones.

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
