import 'dart:io';
import 'dart:ui';

import 'package:equatable/equatable.dart';

import 'package:trickster/src/config/key_value.dart';

enum TricksterLayer { background, bottom, top, overlay }

enum TricksterKeyboard {
  none('none'),
  exclusive('exclusive'),
  onDemand('on_demand');

  const TricksterKeyboard(this.wire);

  final String wire;
}

class SessionConfig extends Equatable {
  const SessionConfig({
    this.layer = TricksterLayer.top,
    this.namespace = 'trickster',
    this.keyboard = TricksterKeyboard.onDemand,
    this.accent,
    this.outputConfig,
  });

  final TricksterLayer layer;
  final String namespace;
  final TricksterKeyboard keyboard;
  final Color? accent;
  final String? outputConfig;

  @override
  List<Object?> get props => [layer, namespace, keyboard, accent, outputConfig];

  Map<String, Object?> toJson() => {
    'layer': layer.name,
    'namespace': namespace,
    'keyboard': keyboard.wire,
    if (accent != null)
      'accent':
          '#${accent!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    if (outputConfig != null) 'outputConfig': outputConfig,
  };

  static SessionConfig fromJson(Map<String, dynamic> json) {
    return SessionConfig(
      layer: _layer(json['layer'] as String?),
      namespace: (json['namespace'] as String?) ?? 'trickster',
      keyboard: _keyboard(json['keyboard'] as String?),
      accent: _color(json['accent'] as String?),
      outputConfig: json['outputConfig'] as String?,
    );
  }

  static SessionConfig parse(String source) {
    final document = KeyValueDocument.parse(source);
    return SessionConfig(
      layer: _layer(document['TRICKSTER_LAYER']),
      namespace: document['TRICKSTER_NAMESPACE'] ?? 'trickster',
      keyboard: _keyboard(document['TRICKSTER_KEYBOARD']),
      accent: _color(document['TRICKSTER_ACCENT']),
      outputConfig: document['TRICKSTER_OUTPUT_CONFIG'],
    );
  }

  static SessionConfig fromEnvironment({
    SessionConfig defaults = const SessionConfig(),
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final layer = env['TRICKSTER_LAYER'];
    final namespace = env['TRICKSTER_NAMESPACE'];
    final keyboard = env['TRICKSTER_KEYBOARD'];
    final accent = env['TRICKSTER_ACCENT'];
    final outputConfig = env['TRICKSTER_OUTPUT_CONFIG'];
    return SessionConfig(
      layer: layer == null ? defaults.layer : _layer(layer),
      namespace: namespace ?? defaults.namespace,
      keyboard: keyboard == null ? defaults.keyboard : _keyboard(keyboard),
      accent: accent == null ? defaults.accent : _color(accent),
      outputConfig: outputConfig ?? defaults.outputConfig,
    );
  }

  static TricksterLayer _layer(String? value) {
    return switch (value) {
      null || '' => TricksterLayer.top,
      'background' => TricksterLayer.background,
      'bottom' => TricksterLayer.bottom,
      'top' => TricksterLayer.top,
      'overlay' => TricksterLayer.overlay,
      _ => throw FormatException('unknown TRICKSTER_LAYER: $value'),
    };
  }

  static TricksterKeyboard _keyboard(String? value) {
    return switch (value) {
      null || '' => TricksterKeyboard.onDemand,
      'none' => TricksterKeyboard.none,
      'exclusive' => TricksterKeyboard.exclusive,
      'on_demand' || 'onDemand' => TricksterKeyboard.onDemand,
      _ => throw FormatException('unknown TRICKSTER_KEYBOARD: $value'),
    };
  }

  static Color? _color(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    var hex = value;
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.length != 6) {
      throw FormatException('TRICKSTER_ACCENT must be #RRGGBB: $value');
    }
    return Color(0xff000000 | int.parse(hex, radix: 16));
  }
}
