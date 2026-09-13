---
title: Modules
description: What each pill does, and how to build a new one.
---

Modules are toggled by name in `settings.json` → `modules`. A name that is not listed renders nothing and starts nothing: no subscriptions, no timers, no D-Bus names.

## Built-in modules

| Name | Pill | Source | Visibility rule |
| --- | --- | --- | --- |
| `clock` | Date caption + `HH:MM`, minute crossfade | Local time, minute-aligned single timer | Always renders |
| `cpu` | `CPU 42%` | `/proc/stat`, 1 Hz shared sampler, reused read buffer | Hidden if unreadable |
| `battery` | Gauge + percent | sysfs `power_supply`, 5 s sampler | Hidden with no `BAT*` device |
| `workspaces` | Focused/urgent names | Sway/Hyprland/niri IPC sockets, auto-detected | Hidden when empty |

Planned, not built: `media` (MPRIS) and `tray` (StatusNotifier). The `dbus` dependency is already declared for them.

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

**2. Pill** (`lib/src/bar/weather.dart`) — a `StatelessWidget` taking `accent` + state, wrapped in `SystemBarCard`, text in `ShellText.systemBarValue`:

```dart
class WeatherPill extends StatelessWidget {
  const WeatherPill({required this.accent, required this.weather, super.key});

  final WallpaperAccent accent;
  final Weather weather;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      child: Text('${weather.degrees}°', style: ShellText.systemBarValue),
    );
  }
}
```

**3. Wiring** — a `NotifierProvider` in `lib/src/state/providers.dart` following `CpuController` (watch `settingsProvider.select((s) => s.includes('weather'))`, empty state when disabled, `alive` flag with cancel-on-dispose), plus one guarded block in `TricksterBarStrip` with a `SystemBarEntrance` wrapper and `RepaintBoundary`:

```dart
if (settings.includes('weather'))
  SystemBarEntrance(
    index: 3,
    horizontal: horizontal,
    child: Padding(
      padding: horizontal
          ? const EdgeInsets.only(right: _cardGap)
          : const EdgeInsets.only(bottom: _cardGap),
      child: RepaintBoundary(
        child: WeatherPill(accent: accent, weather: weather),
      ),
    ),
  ),
```

Then add `'weather'` to the defaults in `settings.dart` and a mapping test in `test/` mirroring the existing ones. The bar, theme, and config layers never change — that is the point of the seams.
