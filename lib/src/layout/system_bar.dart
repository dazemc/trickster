import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';

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

class OutputsConfig extends Equatable {
  const OutputsConfig({
    this.side = SystemBarSide.top,
    this.thickness = defaultThickness,
    this.connectors = const <String>[],
  });

  /// The band used when no explicit thickness is configured.
  static const double defaultThickness = 32;

  /// Largest accepted `system_bar=` thickness. No supported strip needs more
  /// than a few hundred logical pixels; 512 leaves generous room for vertical
  /// bars with inline captions and media controls, while rejecting a
  /// hand-edited value large enough to swallow the output.
  static const double maxThickness = 512;

  /// Makes a programmatic thickness safe for encoding and rendering.
  ///
  /// [parse] rejects non-finite and out-of-range values, but the typed
  /// constructor is public and tests, previews, and JSON round-trips can
  /// still hand the UI a `NaN`, an infinity, or a stale oversized band.
  /// Those values fall back to [defaultThickness] or clamp to
  /// [maxThickness] instead of throwing from `.round()`.
  static double normalizeThickness(double value) {
    if (!value.isFinite || value <= 0) {
      return defaultThickness;
    }
    return math.min(value, maxThickness);
  }

  /// Trims connector names, drops empties, and removes duplicates while
  /// keeping the first occurrence's order. The `system_bar=` grammar uses an
  /// empty list for "every output", so an empty name must never survive as a
  /// phantom connector that matches nothing.
  static List<String> normalizeConnectors(Iterable<String> connectors) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final connector in connectors) {
      final name = connector.trim();
      if (name.isEmpty || !seen.add(name)) {
        continue;
      }
      normalized.add(name);
    }
    return List<String>.unmodifiable(normalized);
  }

  final SystemBarSide side;
  final double thickness;
  final List<String> connectors;

  /// [thickness] with non-finite and out-of-range values normalized. Labels,
  /// sliders, and encoders use this so an invalid programmatic config can
  /// never reach `.round()` or the `system_bar=` grammar.
  double get safeThickness => normalizeThickness(thickness);

  // Spread: see BarSettings — deep equality over the connector list.
  @override
  List<Object?> get props => [side, thickness, ...connectors];

  bool get active =>
      side != SystemBarSide.hidden && thickness.isFinite && thickness > 0;

  Map<String, Object?> toJson() => {
    'side': side.name,
    'thickness': thickness,
    'connectors': connectors,
  };

  static OutputsConfig fromJson(Map<String, dynamic> json) {
    return OutputsConfig(
      side: SystemBarSideGeometry.parse((json['side'] as String?) ?? 'top'),
      thickness: normalizeThickness(
        ((json['thickness'] as num?) ?? defaultThickness).toDouble(),
      ),
      connectors: normalizeConnectors(
        (json['connectors'] as List?)?.whereType<String>() ?? const <String>[],
      ),
    );
  }

  OutputsConfig copyWith({
    SystemBarSide? side,
    double? thickness,
    List<String>? connectors,
  }) {
    return OutputsConfig(
      side: side ?? this.side,
      thickness: thickness ?? this.thickness,
      connectors: connectors ?? this.connectors,
    );
  }

  bool hosts(String connector) =>
      connectors.isEmpty || connectors.contains(connector);

  /// Geometry of the strip inside [outputRect].
  ///
  /// This is preview/test geometry: the running bar currently hands
  /// [thickness] to layer-shell directly, so the half-output clamp here has
  /// no production caller yet. [maxThickness] still bounds every thickness
  /// that arrives through the file, which keeps the raw layer-shell request
  /// from growing without limit.
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

  /// The single `system_bar=` line, without the file header. The file
  /// transport splices this into the existing document so comments and
  /// unrelated keys survive a settings write.
  String encodeLine() {
    if (side == SystemBarSide.hidden) {
      return 'system_bar=hidden';
    }
    final buffer = StringBuffer(
      'system_bar=${side.name},${safeThickness.round()}',
    );
    for (final connector in normalizeConnectors(connectors)) {
      buffer.write(',$connector');
    }
    return '$buffer';
  }

  /// The canonical document written only when no existing file exists. The
  /// `system_bar=` grammar treats an empty connector list as every output.
  String encode() {
    return '# Trickster output configuration\n${encodeLine()}\n';
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
        final parsed = double.parse(parts[1]);
        if (!parsed.isFinite || parsed <= 0 || parsed > maxThickness) {
          throw FormatException(
            'system_bar thickness must be finite, positive, and at most '
            '${maxThickness.round()}: $line',
          );
        }
        thickness = parsed;
      }
      if (parts.length > 2) {
        final names = parts.sublist(2);
        if (names.any((name) => name.isEmpty)) {
          throw FormatException(
            'system_bar connector names must not be empty: $line',
          );
        }
        connectors = normalizeConnectors(names);
      }
    }
    return OutputsConfig(
      side: side,
      thickness: thickness,
      connectors: connectors,
    );
  }
}
