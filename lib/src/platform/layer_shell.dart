import 'package:flutter/services.dart';

import '../config/session.dart';
import '../layout/system_bar.dart';

class LayerShell {
  LayerShell({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('org.trickster.bar/layer_shell');

  final MethodChannel _channel;

  Future<bool> isSupported() async {
    final supported = await _channel.invokeMethod<bool>('supported');
    return supported ?? false;
  }

  Future<List<LayerOutput>> outputs() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('outputs');
    if (raw == null) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (entry) => LayerOutput(
            name: '${entry['name'] ?? ''}',
            width: (entry['width'] as num?)?.toInt() ?? 0,
            height: (entry['height'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<void> configure({
    required OutputsConfig outputs,
    required SessionConfig session,
  }) {
    return _channel.invokeMethod<void>('configure', {
      'side': outputs.side.name,
      'thickness': outputs.thickness.round(),
      'layer': session.layer.name,
      'namespace': session.namespace,
      'keyboard': switch (session.keyboard) {
        TricksterKeyboard.none => 'none',
        TricksterKeyboard.exclusive => 'exclusive',
        TricksterKeyboard.onDemand => 'on_demand',
      },
    });
  }
}

class LayerOutput {
  const LayerOutput({
    required this.name,
    required this.width,
    required this.height,
  });

  final String name;
  final int width;
  final int height;
}
