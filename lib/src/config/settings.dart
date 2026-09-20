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

/// Per-display appearance overrides keyed by connector; absent keys fall
/// back to the global appearance settings on [BarSettings].
class DisplayAppearance extends Equatable {
  const DisplayAppearance({
    this.accent,
    this.accentSource,
    this.accentWallpaperPick,
  });

  final Color? accent;
  final AccentSource? accentSource;
  final String? accentWallpaperPick;

  bool get isEmpty =>
      accent == null && accentSource == null && accentWallpaperPick == null;

  @override
  List<Object?> get props => [accent, accentSource, accentWallpaperPick];

  Map<String, Object?> toJson() => {
    if (accent != null)
      'accent':
          '#${accent!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    if (accentSource != null) 'accent_source': accentSource!.wire,
    if (accentWallpaperPick != null)
      'accent_wallpaper_pick': accentWallpaperPick,
  };

  static DisplayAppearance fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException(
        'settings.display_appearance values must be objects',
      );
    }
    final accent = json['accent'];
    final parsedAccent = colorFromHex(accent);
    if (accent != null && parsedAccent == null) {
      throw FormatException(
        'display appearance accent must be #RRGGBB: $accent',
      );
    }
    final pick = json['accent_wallpaper_pick'];
    if (pick != null && (pick is! String || colorFromHex(pick) == null)) {
      throw const FormatException('display appearance pick must be #RRGGBB');
    }
    return DisplayAppearance(
      accent: parsedAccent,
      accentSource: json['accent_source'] == null
          ? null
          : AccentSource.parse(json['accent_source']),
      accentWallpaperPick: pick as String?,
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

const _unset = Object();

/// Typed options for the CPU meter.
class CpuOptions extends Equatable {
  const CpuOptions({
    this.warn = 0.85,
    this.critical = 0.95,
    this.captionSource = MeterCaptionSource.generic,
    this.captionPrefix,
    this.warnColor,
    this.criticalColor,
    this.sparkline = true,
  });

  final double warn;
  final double critical;
  final MeterCaptionSource captionSource;

  /// Caption text when [captionSource] is custom.
  final String? captionPrefix;

  /// Threshold tints; null keeps the shell defaults.
  final Color? warnColor;
  final Color? criticalColor;

  /// Whether the recent-history sparkline renders.
  final bool sparkline;

  @override
  List<Object?> get props => [
    warn,
    critical,
    captionSource,
    captionPrefix,
    warnColor,
    criticalColor,
    sparkline,
  ];

  Map<String, Object?> toJson() => {
    'warn': warn,
    'critical': critical,
    'caption_source': captionSource.name,
    if (captionPrefix != null) 'caption_prefix': captionPrefix,
    if (warnColor != null) 'warn_color': _hex(warnColor!),
    if (criticalColor != null) 'critical_color': _hex(criticalColor!),
    'sparkline': sparkline,
  };

  CpuOptions copyWith({
    double? warn,
    double? critical,
    MeterCaptionSource? captionSource,
    Object? captionPrefix = _unset,
    Object? warnColor = _unset,
    Object? criticalColor = _unset,
    bool? sparkline,
  }) {
    return CpuOptions(
      warn: warn ?? this.warn,
      critical: critical ?? this.critical,
      captionSource: captionSource ?? this.captionSource,
      captionPrefix: identical(captionPrefix, _unset)
          ? this.captionPrefix
          : captionPrefix as String?,
      warnColor: identical(warnColor, _unset)
          ? this.warnColor
          : warnColor as Color?,
      criticalColor: identical(criticalColor, _unset)
          ? this.criticalColor
          : criticalColor as Color?,
      sparkline: sparkline ?? this.sparkline,
    );
  }

  /// [legacy] is the retired shared `meter` object, consulted when this
  /// document predates per-meter options.
  static CpuOptions fromJson(Object? json, {Object? legacy}) {
    if (json == null && legacy == null) {
      return const CpuOptions();
    }
    if (json != null && json is! Map<String, dynamic>) {
      throw const FormatException('settings.cpu must be an object');
    }
    final decoded = json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final warn = _ratio(decoded['warn'], 'settings.cpu.warn') ?? 0.85;
    final critical =
        _ratio(decoded['critical'], 'settings.cpu.critical') ?? 0.95;
    if (warn >= critical) {
      throw const FormatException('settings.cpu.warn must be below critical');
    }
    return CpuOptions(
      warn: warn,
      critical: critical,
      captionSource: _captionSource(decoded, legacy),
      captionPrefix: _prefix(decoded['caption_prefix']),
      warnColor: _meterColor(decoded['warn_color'], 'settings.cpu.warn_color'),
      criticalColor: _meterColor(
        decoded['critical_color'],
        'settings.cpu.critical_color',
      ),
      sparkline: _sparkline(decoded, legacy),
    );
  }
}

/// Typed options for the GPU meter; the same shape as the CPU's meter keys.
class GpuOptions extends Equatable {
  const GpuOptions({
    this.warn = 0.85,
    this.critical = 0.95,
    this.captionSource = MeterCaptionSource.generic,
    this.captionPrefix,
    this.warnColor,
    this.criticalColor,
    this.sparkline = true,
  });

  final double warn;
  final double critical;
  final MeterCaptionSource captionSource;

  /// Caption text when [captionSource] is custom.
  final String? captionPrefix;

  /// Threshold tints; null keeps the shell defaults.
  final Color? warnColor;
  final Color? criticalColor;

  /// Whether the recent-history sparkline renders.
  final bool sparkline;

  @override
  List<Object?> get props => [
    warn,
    critical,
    captionSource,
    captionPrefix,
    warnColor,
    criticalColor,
    sparkline,
  ];

  Map<String, Object?> toJson() => {
    'warn': warn,
    'critical': critical,
    'caption_source': captionSource.name,
    if (captionPrefix != null) 'caption_prefix': captionPrefix,
    if (warnColor != null) 'warn_color': _hex(warnColor!),
    if (criticalColor != null) 'critical_color': _hex(criticalColor!),
    'sparkline': sparkline,
  };

  GpuOptions copyWith({
    double? warn,
    double? critical,
    MeterCaptionSource? captionSource,
    Object? captionPrefix = _unset,
    Object? warnColor = _unset,
    Object? criticalColor = _unset,
    bool? sparkline,
  }) {
    return GpuOptions(
      warn: warn ?? this.warn,
      critical: critical ?? this.critical,
      captionSource: captionSource ?? this.captionSource,
      captionPrefix: identical(captionPrefix, _unset)
          ? this.captionPrefix
          : captionPrefix as String?,
      warnColor: identical(warnColor, _unset)
          ? this.warnColor
          : warnColor as Color?,
      criticalColor: identical(criticalColor, _unset)
          ? this.criticalColor
          : criticalColor as Color?,
      sparkline: sparkline ?? this.sparkline,
    );
  }

  /// [legacy] is the retired shared `meter` object, consulted when this
  /// document predates per-meter options.
  static GpuOptions fromJson(Object? json, {Object? legacy}) {
    if (json == null && legacy == null) {
      return const GpuOptions();
    }
    if (json != null && json is! Map<String, dynamic>) {
      throw const FormatException('settings.gpu must be an object');
    }
    final decoded = json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final warn = _ratio(decoded['warn'], 'settings.gpu.warn') ?? 0.85;
    final critical =
        _ratio(decoded['critical'], 'settings.gpu.critical') ?? 0.95;
    if (warn >= critical) {
      throw const FormatException('settings.gpu.warn must be below critical');
    }
    return GpuOptions(
      warn: warn,
      critical: critical,
      captionSource: _captionSource(decoded, legacy),
      captionPrefix: _prefix(decoded['caption_prefix']),
      warnColor: _meterColor(decoded['warn_color'], 'settings.gpu.warn_color'),
      criticalColor: _meterColor(
        decoded['critical_color'],
        'settings.gpu.critical_color',
      ),
      sparkline: _sparkline(decoded, legacy),
    );
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

/// How much of the date the clock's caption shows.
enum ClockDateStyle {
  short('short'),
  long('long'),
  weekday('weekday');

  const ClockDateStyle(this.wire);

  final String wire;

  static ClockDateStyle parse(Object? value) {
    if (value == null) {
      return ClockDateStyle.short;
    }
    for (final style in ClockDateStyle.values) {
      if (style.wire == value) {
        return style;
      }
    }
    throw FormatException(
      'settings.clock.date_style must be one of '
      '${ClockDateStyle.values.map((style) => style.wire).join(', ')}',
    );
  }
}

class ClockOptions extends Equatable {
  const ClockOptions({
    this.format = ClockFormat.locale,
    this.showDate = true,
    this.showSeconds = false,
    this.dateStyle = ClockDateStyle.short,
  });

  final ClockFormat format;

  /// Whether the date caption renders beside the time. Vertical strips drop
  /// it regardless.
  final bool showDate;

  /// Whether seconds join the time; the clock then ticks every second.
  final bool showSeconds;

  /// How much of the date the caption shows.
  final ClockDateStyle dateStyle;

  @override
  List<Object?> get props => [format, showDate, showSeconds, dateStyle];

  ClockOptions copyWith({
    ClockFormat? format,
    bool? showDate,
    bool? showSeconds,
    ClockDateStyle? dateStyle,
  }) {
    return ClockOptions(
      format: format ?? this.format,
      showDate: showDate ?? this.showDate,
      showSeconds: showSeconds ?? this.showSeconds,
      dateStyle: dateStyle ?? this.dateStyle,
    );
  }

  Map<String, Object?> toJson() => {
    'format': format.wire,
    'show_date': showDate,
    'show_seconds': showSeconds,
    'date_style': dateStyle.wire,
  };

  static ClockOptions fromJson(Object? json) {
    if (json == null) {
      return const ClockOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.clock must be an object');
    }
    return ClockOptions(
      format: ClockFormat.parse(json['format']),
      showDate: (json['show_date'] as bool?) ?? true,
      showSeconds: (json['show_seconds'] as bool?) ?? false,
      dateStyle: ClockDateStyle.parse(json['date_style']),
    );
  }
}

/// Typed options for the strip's material.
class AppearanceOptions extends Equatable {
  const AppearanceOptions({this.blur = true});

  /// Whether the pills may sit on the compositor's blur when the host
  /// advertises it; false forces the opaque fill.
  final bool blur;

  @override
  List<Object?> get props => [blur];

  Map<String, Object?> toJson() => {'blur': blur};

  static AppearanceOptions fromJson(Object? json) {
    if (json == null) {
      return const AppearanceOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.appearance must be an object');
    }
    return AppearanceOptions(blur: (json['blur'] as bool?) ?? true);
  }
}

/// How much of the media pill the bar shows.
enum MediaMode {
  full('full'),
  semi('semi'),
  compact('compact');

  const MediaMode(this.wire);

  final String wire;

  static MediaMode parse(Object? value) {
    if (value == null) {
      return MediaMode.semi;
    }
    for (final mode in MediaMode.values) {
      if (mode.wire == value) {
        return mode;
      }
    }
    throw FormatException(
      'settings.media.mode must be one of '
      '${MediaMode.values.map((mode) => mode.wire).join(', ')}',
    );
  }
}

/// Typed options for the media pill.
class MediaOptions extends Equatable {
  const MediaOptions({this.mode = MediaMode.semi});

  /// The display mode the pill returns to on relaunch; tapping cycles
  /// transiently from it.
  final MediaMode mode;

  @override
  List<Object?> get props => [mode];

  MediaOptions copyWith({MediaMode? mode}) =>
      MediaOptions(mode: mode ?? this.mode);

  Map<String, Object?> toJson() => {'mode': mode.wire};

  static MediaOptions fromJson(Object? json) {
    if (json == null) {
      return const MediaOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.media must be an object');
    }
    return MediaOptions(mode: MediaMode.parse(json['mode']));
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
  device,
  custom;

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
      'caption_source must be one of '
      '${MeterCaptionSource.values.map((source) => source.name).join(', ')}',
    );
  }
}

/// Caption source for one meter, falling back to the retired shared `meter`
/// object when the document predates per-meter options.
MeterCaptionSource _captionSource(
  Map<String, dynamic> decoded,
  Object? legacy,
) {
  final legacyMap = legacy is Map<String, dynamic> ? legacy : null;
  return MeterCaptionSource.parse(
    decoded['caption_source'] ?? legacyMap?['caption_source'],
  );
}

/// `#RRGGBB` for a meter threshold tint.
String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// A threshold tint: `#RRGGBB`, rejected with [key] in the message otherwise.
Color? _meterColor(Object? value, String key) {
  if (value == null) {
    return null;
  }
  final color = colorFromHex(value);
  if (color == null) {
    throw FormatException('$key must be #RRGGBB: $value');
  }
  return color;
}

/// The custom caption text: strings only, empty values clear the key.
String? _prefix(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('caption_prefix must be a string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Sparkline switch for one meter, falling back to the retired shared `meter`
/// object when the document predates per-meter options.
bool _sparkline(Map<String, dynamic> decoded, Object? legacy) {
  final legacyMap = legacy is Map<String, dynamic> ? legacy : null;
  return (decoded['sparkline'] as bool?) ??
      (legacyMap?['sparkline'] as bool?) ??
      true;
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

/// How the workspace rail paints each pip.
enum PipStyle {
  number('number'),
  dot('dot'),
  roman('roman'),
  image('image');

  const PipStyle(this.wire);

  final String wire;

  static PipStyle parse(Object? value) {
    if (value == null) {
      return PipStyle.number;
    }
    for (final style in PipStyle.values) {
      if (style.wire == value) {
        return style;
      }
    }
    throw FormatException(
      'settings.workspaces.pip_style must be one of '
      '${PipStyle.values.map((style) => style.wire).join(', ')}',
    );
  }
}

/// Typed options for the workspace rail. The retired counts, per-output
/// overrides, and display order stay ignored: placement belongs to the
/// compositor, only the look is configurable.
class WorkspaceOptions extends Equatable {
  const WorkspaceOptions({
    this.pipStyle = PipStyle.number,
    this.imageSource,
    this.imageByWorkspace = const {},
    this.tintSvg = false,
  });

  final PipStyle pipStyle;

  /// Local file the `image` style loads its artwork from when the workspace
  /// has no mapping of its own.
  final String? imageSource;

  /// Per-workspace artwork files, keyed by the workspace name the rail
  /// paints.
  final Map<String, String> imageByWorkspace;

  /// Whether vector artwork recolors to the accent.
  final bool tintSvg;

  @override
  List<Object?> get props => [pipStyle, imageSource, imageByWorkspace, tintSvg];

  Map<String, Object?> toJson() => {
    'pip_style': pipStyle.wire,
    if (imageSource != null) 'image_source': imageSource,
    if (imageByWorkspace.isNotEmpty)
      'image_by_workspace': Map<String, String>.of(imageByWorkspace),
    if (tintSvg) 'tint_svg': true,
  };

  static WorkspaceOptions fromJson(Object? json) {
    if (json == null) {
      return const WorkspaceOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.workspaces must be an object');
    }
    return WorkspaceOptions(
      pipStyle: PipStyle.parse(json['pip_style']),
      imageSource: _pipSource(json['image_source']),
      imageByWorkspace: _pipSources(json['image_by_workspace']),
      tintSvg: (json['tint_svg'] as bool?) ?? false,
    );
  }
}

/// Per-workspace artwork paths: name to file, empty values dropped.
Map<String, String> _pipSources(Object? value) {
  if (value == null) {
    return const {};
  }
  if (value is! Map<String, dynamic>) {
    throw const FormatException(
      'settings.workspaces.image_by_workspace must be an object',
    );
  }
  return {
    for (final entry in value.entries)
      if (_pipSource(entry.value) case final path?)
        if (entry.key.isNotEmpty) entry.key: path,
  };
}

/// The browsed image path is a string; an empty value clears the key.
String? _pipSource(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException(
      'settings.workspaces.image_source must be a string',
    );
  }
  return value.isEmpty ? null : value;
}

/// The versioned settings document. The retired `workspaces` counts,
/// per-output overrides, and display order are ignored on decode: workspace
/// placement belongs to the compositor.
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
    this.displayAppearance = const {},
    this.appearance = const AppearanceOptions(),
    this.workspaces = const WorkspaceOptions(),
    this.cpu = const CpuOptions(),
    this.clock = const ClockOptions(),
    this.battery = const BatteryOptions(),
    this.gpu = const GpuOptions(),
    this.media = const MediaOptions(),
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

  /// Per-display appearance overrides by connector.
  final Map<String, DisplayAppearance> displayAppearance;

  /// Material options for the strip's pills.
  final AppearanceOptions appearance;

  /// Look of the workspace rail's pips.
  final WorkspaceOptions workspaces;
  final CpuOptions cpu;
  final ClockOptions clock;
  final BatteryOptions battery;
  final GpuOptions gpu;
  final MediaOptions media;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the module list.
  @override
  List<Object?> get props => [
    revision,
    accent,
    locale,
    accentSource,
    accentWallpaperPick,
    ...displayAppearance.entries.map(
      (entry) => Object.hash(entry.key, entry.value),
    ),
    appearance,
    workspaces,
    ...modules,
    cpu,
    clock,
    battery,
    gpu,
    media,
  ];

  bool includes(String module) => modules.contains(module);

  /// The zone [module] renders in: the explicit placement or the default.
  ModuleZone zoneFor(String module) =>
      modulePlacement[module] ?? defaultModuleZone(module);

  /// The accent source [output] resolves: its override, else the global key.
  AccentSource accentSourceFor(String? output) =>
      displayAppearance[output]?.accentSource ?? accentSource;

  /// The configured accent [output] resolves: its override, else global.
  Color? accentFor(String? output) =>
      displayAppearance[output]?.accent ?? accent;

  /// The wallpaper pick [output] resolves: its override, else global.
  String? accentWallpaperPickFor(String? output) =>
      displayAppearance[output]?.accentWallpaperPick ?? accentWallpaperPick;

  /// Whether any display samples the wallpaper; the sampler starts for this.
  bool get usesWallpaperAccent =>
      accentSource == AccentSource.wallpaper ||
      displayAppearance.values.any(
        (appearance) => appearance.accentSource == AccentSource.wallpaper,
      );

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
    if (displayAppearance.isNotEmpty)
      'display_appearance': {
        for (final entry in displayAppearance.entries)
          if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
      },
    'cpu': cpu.toJson(),
    'clock': clock.toJson(),
    'battery': battery.toJson(),
    'gpu': gpu.toJson(),
    'media': media.toJson(),
    'appearance': appearance.toJson(),
    'workspaces': workspaces.toJson(),
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
      displayAppearance: displayAppearance,
      appearance: appearance,
      workspaces: workspaces,
      modules: modules,
      modulePlacement: modulePlacement,
      cpu: cpu,
      clock: clock,
      battery: battery,
      gpu: gpu,
      media: media,
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
      displayAppearance: displayAppearance,
      appearance: appearance,
      workspaces: workspaces,
      modules: modules,
      modulePlacement: modulePlacement,
      cpu: cpu,
      clock: clock,
      battery: battery,
      gpu: gpu,
      media: media,
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
      displayAppearance: displayAppearance,
      appearance: appearance,
      workspaces: workspaces,
      modules: modules,
      modulePlacement: modulePlacement,
      cpu: cpu,
      clock: clock,
      battery: battery,
      gpu: gpu,
      media: media,
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
    GpuOptions? gpu,
    MediaOptions? media,
    String? locale,
    AccentSource? accentSource,
    String? accentWallpaperPick,
    Map<String, DisplayAppearance>? displayAppearance,
    AppearanceOptions? appearance,
    WorkspaceOptions? workspaces,
  }) {
    return BarSettings(
      revision: revision ?? this.revision,
      accent: accent ?? this.accent,
      // copyWith cannot clear the locale; use withLocale(null).
      locale: locale ?? this.locale,
      accentSource: accentSource ?? this.accentSource,
      accentWallpaperPick: accentWallpaperPick ?? this.accentWallpaperPick,
      displayAppearance: displayAppearance ?? this.displayAppearance,
      appearance: appearance ?? this.appearance,
      workspaces: workspaces ?? this.workspaces,
      modules: modules ?? this.modules,
      modulePlacement: modulePlacement ?? this.modulePlacement,
      cpu: cpu ?? this.cpu,
      clock: clock ?? this.clock,
      battery: battery ?? this.battery,
      gpu: gpu ?? this.gpu,
      media: media ?? this.media,
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
    final legacyMeter = decoded['meter'];
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
      displayAppearance: _displayAppearance(decoded['display_appearance']),
      appearance: AppearanceOptions.fromJson(decoded['appearance']),
      workspaces: WorkspaceOptions.fromJson(decoded['workspaces']),
      cpu: CpuOptions.fromJson(decoded['cpu'], legacy: legacyMeter),
      clock: ClockOptions.fromJson(decoded['clock']),
      battery: BatteryOptions.fromJson(decoded['battery']),
      gpu: GpuOptions.fromJson(decoded['gpu'], legacy: legacyMeter),
      media: MediaOptions.fromJson(decoded['media']),
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

  static Map<String, DisplayAppearance> _displayAppearance(Object? value) {
    if (value == null) {
      return const {};
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'settings.display_appearance must be an object',
      );
    }
    return {
      for (final entry in value.entries)
        entry.key: DisplayAppearance.fromJson(entry.value),
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
