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

class BarSettings extends Equatable {
  const BarSettings({
    this.revision = 1,
    this.accent,
    this.modules = const [
      'workspaces',
      'tray',
      'media',
      'cpu',
      'gpu',
      'battery',
      'clock',
    ],
    this.workspaces = const WorkspaceOptions(),
  });

  final int revision;
  final Color? accent;
  final List<String> modules;
  final WorkspaceOptions workspaces;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the module list.
  @override
  List<Object?> get props => [revision, accent, ...modules, workspaces];

  bool includes(String module) => modules.contains(module);

  Map<String, Object?> toJson() => {
    'revision': revision,
    if (accent != null)
      'accent':
          '#${accent!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'modules': modules,
    'workspaces': workspaces.toJson(),
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  BarSettings copyWith({
    int? revision,
    Color? accent,
    List<String>? modules,
    WorkspaceOptions? workspaces,
  }) {
    return BarSettings(
      revision: revision ?? this.revision,
      accent: accent ?? this.accent,
      modules: modules ?? this.modules,
      workspaces: workspaces ?? this.workspaces,
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
    return BarSettings(
      revision: revision,
      accent: _color(decoded['accent']),
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
