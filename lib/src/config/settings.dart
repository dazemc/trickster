import 'dart:convert';
import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Typed options for the workspace rail.
class WorkspaceOptions extends Equatable {
  const WorkspaceOptions({this.showEmpty = true, this.max = 9});

  final bool showEmpty;
  final int max;

  @override
  List<Object?> get props => [showEmpty, max];

  Map<String, Object?> toJson() => {'show_empty': showEmpty, 'max': max};

  static WorkspaceOptions fromJson(Object? json) {
    if (json == null) {
      return const WorkspaceOptions();
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings.workspaces must be an object');
    }
    final showEmpty = json['show_empty'];
    if (showEmpty != null && showEmpty is! bool) {
      throw const FormatException(
        'settings.workspaces.show_empty must be a boolean',
      );
    }
    final max = json['max'];
    if (max != null && (max is! int || max < 1 || max > 64)) {
      throw const FormatException('settings.workspaces.max must be 1..64');
    }
    return WorkspaceOptions(
      showEmpty: showEmpty as bool? ?? true,
      max: max as int? ?? 9,
    );
  }
}

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
    this.locale,
    this.accentSource = AccentSource.custom,
    this.workspaces = const WorkspaceOptions(),
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
  final String? locale;
  final AccentSource accentSource;
  final WorkspaceOptions workspaces;
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
    ...modules,
    workspaces,
    cpu,
    clock,
    battery,
    meter,
  ];

  bool includes(String module) => modules.contains(module);

  Map<String, Object?> toJson() => {
    'revision': revision,
    if (accent != null)
      'accent':
          '#${accent!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'modules': modules,
    if (locale != null) 'locale': locale,
    'accent_source': accentSource.wire,
    'workspaces': workspaces.toJson(),
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
      modules: modules,
      workspaces: workspaces,
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
      modules: modules,
      workspaces: workspaces,
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
    WorkspaceOptions? workspaces,
    CpuOptions? cpu,
    ClockOptions? clock,
    BatteryOptions? battery,
    MeterOptions? meter,
    String? locale,
    AccentSource? accentSource,
  }) {
    return BarSettings(
      revision: revision ?? this.revision,
      accent: accent ?? this.accent,
      // copyWith cannot clear the locale; use withLocale(null).
      locale: locale ?? this.locale,
      accentSource: accentSource ?? this.accentSource,
      modules: modules ?? this.modules,
      workspaces: workspaces ?? this.workspaces,
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
      workspaces: WorkspaceOptions.fromJson(decoded['workspaces']),
      cpu: CpuOptions.fromJson(decoded['cpu']),
      clock: ClockOptions.fromJson(decoded['clock']),
      battery: BatteryOptions.fromJson(decoded['battery']),
      meter: MeterOptions.fromJson(decoded['meter']),
    );
  }

  static Color? _color(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    var hex = value;
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.length != 6) {
      throw FormatException('accent must be #RRGGBB: $value');
    }
    return Color(0xff000000 | int.parse(hex, radix: 16));
  }
}
