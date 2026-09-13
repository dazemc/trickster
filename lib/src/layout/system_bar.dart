import 'dart:math' as math;
import 'dart:ui';

enum SystemBarSide { top, bottom, left, right, hidden }

extension SystemBarSideGeometry on SystemBarSide {
  bool get isHorizontal =>
      this == SystemBarSide.top || this == SystemBarSide.bottom;

  static SystemBarSide parse(String value) {
    return switch (value) {
      'top' => SystemBarSide.top,
      'bottom' => SystemBarSide.bottom,
      'left' => SystemBarSide.left,
      'right' => SystemBarSide.right,
      'hidden' => SystemBarSide.hidden,
      _ => throw FormatException('unknown system bar side: $value'),
    };
  }
}

class OutputsConfig {
  const OutputsConfig({
    this.side = SystemBarSide.top,
    this.thickness = 32,
    this.connectors = const <String>[],
  });

  final SystemBarSide side;
  final double thickness;
  final List<String> connectors;

  bool get active => side != SystemBarSide.hidden && thickness > 0;

  Map<String, Object?> toJson() => {
    'side': side.name,
    'thickness': thickness,
    'connectors': connectors,
  };

  static OutputsConfig fromJson(Map<String, dynamic> json) {
    return OutputsConfig(
      side: SystemBarSideGeometry.parse(
        (json['side'] as String?) ?? 'top',
      ),
      thickness: ((json['thickness'] as num?) ?? 32).toDouble(),
      connectors: (json['connectors'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
    );
  }

  bool hosts(String connector) =>
      connectors.isEmpty || connectors.contains(connector);

  Rect stripWithin(Rect outputRect) {
    if (!active || outputRect.isEmpty) {
      return Rect.zero;
    }
    if (side.isHorizontal) {
      final thickness = math.min(this.thickness, outputRect.height / 2.0);
      return side == SystemBarSide.top
          ? Rect.fromLTWH(
              outputRect.left,
              outputRect.top,
              outputRect.width,
              thickness,
            )
          : Rect.fromLTWH(
              outputRect.left,
              outputRect.bottom - thickness,
              outputRect.width,
              thickness,
            );
    }
    final thickness = math.min(this.thickness, outputRect.width / 2.0);
    return side == SystemBarSide.left
        ? Rect.fromLTWH(
            outputRect.left,
            outputRect.top,
            thickness,
            outputRect.height,
          )
        : Rect.fromLTWH(
            outputRect.right - thickness,
            outputRect.top,
            thickness,
            outputRect.height,
          );
  }

  static OutputsConfig parse(String source) {
    var side = SystemBarSide.top;
    var thickness = 32.0;
    var connectors = const <String>[];
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) {
        throw FormatException('expected KEY=VALUE, found: $line');
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key != 'system_bar') {
        continue;
      }
      if (value == 'hidden') {
        return const OutputsConfig(side: SystemBarSide.hidden, thickness: 0);
      }
      final parts = value.split(',').map((part) => part.trim()).toList();
      if (parts.isEmpty || parts.first.isEmpty) {
        throw FormatException('system_bar is missing a side: $line');
      }
      side = SystemBarSideGeometry.parse(parts.first);
      if (parts.length > 1) {
        thickness = double.parse(parts[1]);
        if (thickness <= 0) {
          throw FormatException('system_bar thickness must be positive: $line');
        }
      }
      if (parts.length > 2) {
        connectors = parts.sublist(2);
      }
    }
    return OutputsConfig(
      side: side,
      thickness: thickness,
      connectors: connectors,
    );
  }
}
