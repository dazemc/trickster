import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:trickster/src/services/pipewire.dart';

/// A capture that never reaches the runner: records start/stop and lets a
/// test push synthetic frames.
class FakePipeWireCapture extends PipeWireCapture {
  FakePipeWireCapture({this.startResult = true})
    : super(channel: const MethodChannel('test/trickster/pipewire'));

  final bool startResult;
  final List<int> starts = <int>[];
  final List<int> stops = <int>[];
  final StreamController<PipeWireFrame> controller =
      StreamController<PipeWireFrame>.broadcast();
  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<bool> start() async {
    starts.add(1);
    _running = startResult;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stops.add(1);
    _running = false;
  }

  @override
  Stream<PipeWireFrame> get frames => controller.stream;

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  /// Pushes one F32 stereo batch, as the runner's channel would.
  void emit(List<double> samples, {int rate = 48000, int channels = 2}) {
    final bytes = Float32List.fromList(samples).buffer.asUint8List();
    controller.add(PipeWireFrame(data: bytes, rate: rate, channels: channels));
  }
}
