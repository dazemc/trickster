import 'dart:convert';
import 'dart:ui';

import 'package:equatable/equatable.dart';

class BarSettings extends Equatable {
  const BarSettings({
    this.revision = 1,
    this.accent,
    this.modules = const ['workspaces', 'cpu', 'gpu', 'battery', 'clock'],
  });

  final int revision;
  final Color? accent;
  final List<String> modules;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the module list.
  @override
  List<Object?> get props => [revision, accent, ...modules];

  bool includes(String module) => modules.contains(module);

  Map<String, Object?> toJson() => {
    'revision': revision,
    if (accent != null)
      'accent':
          '#${accent!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'modules': modules,
  };

  String encode() => '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  BarSettings copyWith({
    int? revision,
    Color? accent,
    List<String>? modules,
  }) {
    return BarSettings(
      revision: revision ?? this.revision,
      accent: accent ?? this.accent,
      modules: modules ?? this.modules,
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
      throw const FormatException('settings.json revision must be a positive integer');
    }
    final modules = decoded['modules'];
    return BarSettings(
      revision: revision,
      accent: _color(decoded['accent']),
      modules: modules is List
          ? modules.whereType<String>().toList(growable: false)
          : const ['workspaces', 'cpu', 'gpu', 'battery', 'clock'],
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
