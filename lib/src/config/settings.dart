import 'dart:convert';
import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Where the bar's accent comes from.
enum AccentSource {
  custom('custom'),
  wallpaper('wallpaper');

  const AccentSource(this.wire);

  final String wire;

  static AccentSource parse(Object? value) {
    if (value == null) {
      return AccentSource.custom;
    }
    for (final source in AccentSource.values) {
      if (source.wire == value) {
        return source;
      }
    }
    throw FormatException(
      'settings.accent_source must be one of '
      '${AccentSource.values.map((source) => source.wire).join(', ')}',
    );
  }
}

/// Where a module sits along the strip's main axis.
enum ModuleZone {
  leading('leading'),
  center('center'),
  trailing('trailing');

  const ModuleZone(this.wire);

  final String wire;

  static ModuleZone parse(Object? value) {
    for (final zone in ModuleZone.values) {
      if (zone.wire == value) {
        return zone;
      }
    }
    throw FormatException(
      'settings.module_placement values must be one of '
      '${ModuleZone.values.map((zone) => zone.wire).join(', ')}',
    );
  }
}

/// The zone a module takes when `module_placement` does not name it,
/// mirroring Denial's bar: tray leading, workspaces centered, rest trailing.
ModuleZone defaultModuleZone(String module) {
  return switch (module) {
    'tray' => ModuleZone.leading,
    'workspaces' => ModuleZone.center,
    _ => ModuleZone.trailing,
  };
}

/// Typed options for the CPU meter.
class CpuOptions extends Equatable {
  const CpuOptions({this.warn = 0.85, this.critical = 0.95});

  final double warn;
  final double critical;

  @override
  List<Object?> get props => [warn, critical];

  Map<String, Object?> toJson() => {'warn': warn, 'critical': critical};

  static CpuOptions fromJson(Object? json) {
    if (json == null) {
      return const CpuOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.cpu must be an object');
    }
    final warn = _ratio(json['warn'], 'settings.cpu.warn') ?? 0.85;
    final critical = _ratio(json['critical'], 'settings.cpu.critical') ?? 0.95;
    if (warn >= critical) {
      throw const FormatException('settings.cpu.warn must be below critical');
    }
    return CpuOptions(warn: warn, critical: critical);
  }
}

/// Typed options for the clock pill.
enum ClockFormat {
  locale('locale'),
  hour24('24h'),
  hour12('12h');

  const ClockFormat(this.wire);

  final String wire;

  static ClockFormat parse(Object? value) {
    if (value == null) {
      return ClockFormat.locale;
    }
    for (final format in ClockFormat.values) {
      if (format.wire == value) {
        return format;
      }
    }
    throw FormatException(
      'settings.clock.format must be one of '
      '${ClockFormat.values.map((format) => format.wire).join(', ')}',
    );
  }
}

class ClockOptions extends Equatable {
  const ClockOptions({this.format = ClockFormat.locale});

  final ClockFormat format;

  @override
  List<Object?> get props => [format];

  Map<String, Object?> toJson() => {'format': format.wire};

  static ClockOptions fromJson(Object? json) {
    if (json == null) {
      return const ClockOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.clock must be an object');
    }
    return ClockOptions(format: ClockFormat.parse(json['format']));
  }
}

/// Typed options for the battery pill.
class BatteryOptions extends Equatable {
  const BatteryOptions({this.warn = 20, this.critical = 10});

  final int warn;
  final int critical;

  @override
  List<Object?> get props => [warn, critical];

  Map<String, Object?> toJson() => {'warn': warn, 'critical': critical};

  static BatteryOptions fromJson(Object? json) {
    if (json == null) {
      return const BatteryOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.battery must be an object');
    }
    final warn = _percent(json['warn'], 'settings.battery.warn') ?? 20;
    final critical =
        _percent(json['critical'], 'settings.battery.critical') ?? 10;
    if (critical >= warn) {
      throw const FormatException(
        'settings.battery.critical must be below warn',
      );
    }
    return BatteryOptions(warn: warn, critical: critical);
  }
}

/// Where meter captions come from.
enum MeterCaptionSource {
  generic,
  device;

  static MeterCaptionSource parse(Object? value) {
    if (value == null) {
      return MeterCaptionSource.generic;
    }
    for (final source in MeterCaptionSource.values) {
      if (source.name == value) {
        return source;
      }
    }
    throw FormatException(
      'settings.meter.caption_source must be one of '
      '${MeterCaptionSource.values.map((source) => source.name).join(', ')}',
    );
  }
}

class MeterOptions extends Equatable {
  const MeterOptions({this.captionSource = MeterCaptionSource.generic});

  final MeterCaptionSource captionSource;

  @override
  List<Object?> get props => [captionSource];

  Map<String, Object?> toJson() => {'caption_source': captionSource.name};

  static MeterOptions fromJson(Object? json) {
    if (json == null) {
      return const MeterOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.meter must be an object');
    }
    return MeterOptions(
      captionSource: MeterCaptionSource.parse(json['caption_source']),
    );
  }
}

double? _ratio(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! num || value < 0 || value > 1) {
    throw FormatException('$key must be between 0 and 1');
  }
  return value.toDouble();
}

int? _percent(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 1 || value > 100) {
    throw FormatException('$key must be between 1 and 100');
  }
  return value;
}

/// `#RRGGBB` (with or without the hash) to an opaque [Color].
Color? colorFromHex(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  var hex = value;
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  if (hex.length != 6) {
    return null;
  }
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xff000000 | parsed);
}

/// The versioned settings document. The retired `workspaces` section
/// (counts, per-output overrides, display order) is ignored on decode:
/// workspace placement belongs to the compositor.
class BarSettings extends Equatable {
  /// Every module the bar can run, in the default strip order.
  static const List<String> knownModules = [
    'workspaces',
    'tray',
    'media',
    'cpu',
    'gpu',
    'battery',
    'clock',
  ];

  const BarSettings({
    this.revision = 1,
    this.accent,
    this.modules = knownModules,
    this.modulePlacement = const {},
    this.locale,
    this.accentSource = AccentSource.custom,
    this.accentWallpaperPick,
    this.cpu = const CpuOptions(),
    this.clock = const ClockOptions(),
    this.battery = const BatteryOptions(),
    this.meter = const MeterOptions(),
  });

  /// Supported UI language tag (`en`, `zh`); null follows the system.
  static const List<String> knownLocales = ['en', 'zh'];

  final int revision;
  final Color? accent;
  final List<String> modules;

  /// Explicit zone per module; absent names fall back to
  /// [defaultModuleZone].
  final Map<String, ModuleZone> modulePlacement;
  final String? locale;
  final AccentSource accentSource;

  /// Hex accent chosen from the wallpaper's candidates; null uses the
  /// dominant one.
  final String? accentWallpaperPick;
  final CpuOptions cpu;
  final ClockOptions clock;
  final BatteryOptions battery;
  final MeterOptions meter;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the module list.
  @override
  List<Object?> get props => [
    revision,
    accent,
    locale,
    accentSource,
    accentWallpaperPick,
    ...modules,
    cpu,
    clock,
    battery,
    meter,
  ];

  bool includes(String module) => modules.contains(module);

  /// The zone [module] renders in: the explicit placement or the default.
  ModuleZone zoneFor(String module) =>
      modulePlacement[module] ?? defaultModuleZone(module);

  Map<String, Object?> toJson() => {
    'revision': revision,
    if (accent != null)
      'accent':
          '#${accent!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'modules': modules,
    if (modulePlacement.isNotEmpty)
      'module_placement': {
        for (final entry in modulePlacement.entries)
          entry.key: entry.value.wire,
      },
    if (locale != null) 'locale': locale,
    'accent_source': accentSource.wire,
    if (accentWallpaperPick != null)
      'accent_wallpaper_pick': accentWallpaperPick,
    'cpu': cpu.toJson(),
    'clock': clock.toJson(),
    'battery': battery.toJson(),
    'meter': meter.toJson(),
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Same settings with the accent replaced, clearing it when [accent] is
  /// null (the default accent applies again).
  BarSettings withAccent(Color? accent) {
    return BarSettings(
      revision: revision,
      accent: accent,
      locale: locale,
      accentSource: accentSource,
      accentWallpaperPick: accentWallpaperPick,
      modules: modules,
      modulePlacement: modulePlacement,
      cpu: cpu,
      clock: clock,
      battery: battery,
      meter: meter,
    );
  }

  /// Same settings with the UI language replaced, clearing it when [locale]
  /// is null (the system locale applies again).
  BarSettings withLocale(String? locale) {
    return BarSettings(
      revision: revision,
      accent: accent,
      locale: locale,
      accentSource: accentSource,
      accentWallpaperPick: accentWallpaperPick,
      modules: modules,
      modulePlacement: modulePlacement,
      cpu: cpu,
      clock: clock,
      battery: battery,
      meter: meter,
    );
  }

  /// Same settings with the wallpaper pick replaced; null clears it so the
  /// dominant candidate applies again.
  BarSettings withAccentWallpaperPick(String? pick) {
    return BarSettings(
      revision: revision,
      accent: accent,
      locale: locale,
      accentSource: accentSource,
      accentWallpaperPick: pick,
      modules: modules,
      modulePlacement: modulePlacement,
      cpu: cpu,
      clock: clock,
      battery: battery,
      meter: meter,
    );
  }

  BarSettings copyWith({
    int? revision,
    Color? accent,
    List<String>? modules,
    Map<String, ModuleZone>? modulePlacement,
    CpuOptions? cpu,
    ClockOptions? clock,
    BatteryOptions? battery,
    MeterOptions? meter,
    String? locale,
    AccentSource? accentSource,
    String? accentWallpaperPick,
  }) {
    return BarSettings(
      revision: revision ?? this.revision,
      accent: accent ?? this.accent,
      // copyWith cannot clear the locale; use withLocale(null).
      locale: locale ?? this.locale,
      accentSource: accentSource ?? this.accentSource,
      accentWallpaperPick: accentWallpaperPick ?? this.accentWallpaperPick,
      modules: modules ?? this.modules,
      modulePlacement: modulePlacement ?? this.modulePlacement,
      cpu: cpu ?? this.cpu,
      clock: clock ?? this.clock,
      battery: battery ?? this.battery,
      meter: meter ?? this.meter,
    );
  }

  static BarSettings decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('settings.json must be an object');
    }
    return BarSettings.fromJson(decoded);
  }

  static BarSettings fromJson(Map<String, dynamic> decoded) {
    final revision = decoded['revision'];
    if (revision is! int || revision <= 0) {
      throw const FormatException(
        'settings.json revision must be a positive integer',
      );
    }
    final modules = decoded['modules'];
    final locale = decoded['locale'];
    if (locale != null && !knownLocales.contains(locale)) {
      throw FormatException(
        'settings.locale must be one of ${knownLocales.join(', ')}',
      );
    }
    return BarSettings(
      revision: revision,
      accent: _color(decoded['accent']),
      locale: locale is String ? locale : null,
      accentSource: AccentSource.parse(decoded['accent_source']),
      accentWallpaperPick: _accentPick(decoded['accent_wallpaper_pick']),
      modules: modules is List
          ? modules.whereType<String>().toList(growable: false)
          : const [
              'workspaces',
              'tray',
              'media',
              'cpu',
              'gpu',
              'battery',
              'clock',
            ],
      modulePlacement: _modulePlacement(decoded['module_placement']),
      cpu: CpuOptions.fromJson(decoded['cpu']),
      clock: ClockOptions.fromJson(decoded['clock']),
      battery: BatteryOptions.fromJson(decoded['battery']),
      meter: MeterOptions.fromJson(decoded['meter']),
    );
  }

  static Map<String, ModuleZone> _modulePlacement(Object? value) {
    if (value == null) {
      return const {};
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'settings.module_placement must be an object',
      );
    }
    return {
      for (final entry in value.entries)
        entry.key: ModuleZone.parse(entry.value),
    };
  }

  static Color? _color(Object? value) {
    final color = colorFromHex(value);
    if (value != null && color == null) {
      throw FormatException('accent must be #RRGGBB: $value');
    }
    return color;
  }

  static String? _accentPick(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || colorFromHex(value) == null) {
      throw const FormatException(
        'settings.accent_wallpaper_pick must be #RRGGBB',
      );
    }
    return value;
  }
}
