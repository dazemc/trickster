import 'package:flutter/services.dart';

import '../config/session.dart';
import '../layout/system_bar.dart';

class LayerShell {
  LayerShell({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('org.trickster.bar/layer_shell');

  final MethodChannel _channel;

  Future<bool> isSupported() async {
    final supported = await _channel.invokeMethod<bool>('supported');
    return supported ?? false;
  }

  /// Whether the compositor advertises `ext-background-effect-v1`. Probed
  /// once natively and cached for the process.
  Future<bool> blurSupported() async {
    final supported = await _channel.invokeMethod<bool>('blur');
    return supported ?? false;
  }

  /// Enables or disables the background blur on one strip surface. Only
  /// meaningful when [blurSupported] is true.
  Future<void> setBlur({required int viewId, required bool enabled}) {
    return _channel.invokeMethod<void>('setBlur', {
      'viewId': viewId,
      'enabled': enabled,
    });
  }

  Future<List<LayerOutput>> outputs() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('outputs');
    if (raw == null) {
      return const [];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(
          (entry) => LayerOutput(
            name: '${entry['name'] ?? ''}',
            viewId: (entry['viewId'] as num?)?.toInt() ?? -1,
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

  /// Creates a hidden fullscreen overlay surface for a tray menu on the same
  /// output as [barViewId]. [side] is the strip's edge, so the surface can
  /// anchor against the opposite (unreserved) edge. Returns the new menu view
  /// id, or null when no layer-shell surface could be created.
  Future<int?> openMenuSurface({required int barViewId, required String side}) {
    return _channel.invokeMethod<int>('menuOpen', {
      'barViewId': barViewId,
      'side': side,
    });
  }

  /// Maps a menu surface created with [openMenuSurface] once its session is
  /// ready to render.
  Future<void> showMenuSurface({required int viewId}) {
    return _channel.invokeMethod<void>('menuShow', {'viewId': viewId});
  }

  /// Destroys a menu surface and its Flutter view.
  Future<void> closeMenuSurface({required int viewId}) {
    return _channel.invokeMethod<void>('menuClose', {'viewId': viewId});
  }
}

class LayerOutput {
  const LayerOutput({
    required this.name,
    this.viewId = -1,
    required this.width,
    required this.height,
  });

  /// Connector name when the host exposes one (`HDMI-A-1`), else the model.
  final String name;

  /// The Flutter view of the layer surface on this output.
  final int viewId;
  final int width;
  final int height;
}

/// The outputs that host a strip: every one when the config names no
/// connectors, otherwise the named ones.
List<LayerOutput> hostedOutputs(
  List<LayerOutput> outputs,
  OutputsConfig config,
) {
  return outputs
      .where((output) => config.hosts(output.name))
      .toList(growable: false);
}
