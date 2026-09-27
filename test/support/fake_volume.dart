import 'dart:async';

import 'package:flutter/services.dart';
import 'package:trickster/src/services/volume.dart';

/// A volume watcher that never reaches the runner: records start/stop/set
/// and lets a test push synthetic readings.
class FakePipeWireVolume extends PipeWireVolume {
  FakePipeWireVolume({this.startResult = true})
    : super(channel: const MethodChannel('test/trickster/volume'));

  final bool startResult;
  final List<int> starts = <int>[];
  final List<int> stops = <int>[];
  final List<double> sets = <double>[];
  final StreamController<SinkVolume> controller =
      StreamController<SinkVolume>.broadcast();
  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  Stream<SinkVolume> get levels => controller.stream;

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
  Future<void> set(double volume) async {
    sets.add(volume);
  }

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  /// Pushes one reading, as the runner's channel would.
  void emit(double volume, {bool muted = false}) {
    controller.add(SinkVolume(volume: volume, muted: muted));
  }
}
