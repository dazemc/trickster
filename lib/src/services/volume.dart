import 'dart:async';

import 'package:flutter/services.dart';

/// One default-sink reading: the average channel volume (0..1) and the mute
/// flag.
class SinkVolume {
  const SinkVolume({required this.volume, required this.muted});

  final double volume;
  final bool muted;
}

/// The runner's default-sink volume watcher. [start] connects to PipeWire and
/// follows WirePlumber's default sink, [levels] carries each reading, and
/// [set] writes every channel of that sink.
class PipeWireVolume {
  PipeWireVolume({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('org.trickster.bar/volume') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<SinkVolume> _levels =
      StreamController<SinkVolume>.broadcast();
  var _running = false;

  Stream<SinkVolume> get levels => _levels.stream;

  bool get isRunning => _running;

  Future<bool> start() async {
    if (_running) {
      return true;
    }
    final started = await _channel.invokeMethod<bool>('volumeStart') ?? false;
    _running = started;
    return started;
  }

  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    await _channel.invokeMethod<void>('volumeStop');
  }

  Future<void> set(double volume) => _channel.invokeMethod<void>('volumeSet', {
    'volume': volume.clamp(0.0, 1.0),
  });

  void dispose() {
    _running = false;
    _channel.setMethodCallHandler(null);
    _levels.close();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'volume' || !_running) {
      return;
    }
    final args = call.arguments;
    if (args is! Map) {
      return;
    }
    final volume = args['volume'];
    final muted = args['muted'];
    if (volume is! num || muted is! bool) {
      return;
    }
    _levels.add(
      SinkVolume(volume: volume.toDouble().clamp(0.0, 1.0), muted: muted),
    );
  }
}
