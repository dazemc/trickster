import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One delivered batch of interleaved F32 PCM from the default sink's
/// monitor. [samples] is a view over the runner's payload when its offset
/// allows, a copy otherwise.
class PipeWireFrame {
  PipeWireFrame({
    required Uint8List data,
    required this.rate,
    required this.channels,
  }) : samples = _samplesOf(data);

  /// Interleaved samples in [-1, 1] audio range.
  final Float32List samples;
  final int rate;

  /// Channels per sample frame; always positive.
  final int channels;

  /// Sample frames in this batch (one per channel set).
  int get frames => samples.length ~/ channels;

  /// The channel decodes payloads as views into the message buffer, and the
  /// view may start off a 4-byte boundary; realign before viewing as F32.
  static Float32List _samplesOf(Uint8List data) {
    final length = data.lengthInBytes & ~3;
    final offset = data.offsetInBytes;
    if (offset % 4 == 0) {
      return data.buffer.asFloat32List(offset, length ~/ 4);
    }
    final aligned = Uint8List(length)..setRange(0, length, data);
    return aligned.buffer.asFloat32List(0, length ~/ 4);
  }
}

/// The runner's in-process PipeWire capture. One stream at a time: [start]
/// opens the default sink's monitor, [frames] carries PCM batches, and [stop]
/// disconnects without leaving a subscription behind. The stream is only
/// created while something consumes the levels.
class PipeWireCapture {
  PipeWireCapture({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('org.trickster.bar/pipewire') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<PipeWireFrame> _frames =
      StreamController<PipeWireFrame>.broadcast();
  var _running = false;

  Stream<PipeWireFrame> get frames => _frames.stream;

  bool get isRunning => _running;

  /// Opens the monitor; false when PipeWire has no default sink or the
  /// stream fails to connect. Idempotent while running.
  Future<bool> start() async {
    if (_running) {
      return true;
    }
    final started = await _channel.invokeMethod<bool>('pipewireStart') ?? false;
    _running = started;
    return started;
  }

  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    await _channel.invokeMethod<void>('pipewireStop');
  }

  void dispose() {
    _running = false;
    _channel.setMethodCallHandler(null);
    _frames.close();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'frame' || !_running) {
      return;
    }
    final args = call.arguments;
    if (args is! Map) {
      return;
    }
    final data = args['data'];
    final rate = args['rate'];
    final channels = args['channels'];
    if (data is! Uint8List ||
        rate is! int ||
        channels is! int ||
        channels <= 0 ||
        data.lengthInBytes < channels * 4) {
      return;
    }
    _frames.add(PipeWireFrame(data: data, rate: rate, channels: channels));
  }
}
