import 'dart:async';

import 'package:trickster/src/services/bands.dart';

/// An analyzer that never spawns a worker: records start/stop and lets a
/// test push synthetic band levels.
class FakeBandAnalyzer extends BandAnalyzer {
  FakeBandAnalyzer({this.startResult = true});

  final bool startResult;
  final List<int> starts = <int>[];
  final List<int> stops = <int>[];
  final StreamController<List<double>> controller =
      StreamController<List<double>>.broadcast();
  final StreamController<void> failureController =
      StreamController<void>.broadcast();
  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  Stream<List<double>> get levels => controller.stream;

  @override
  Stream<void> get failures => failureController.stream;

  /// Signals a terminal worker failure, as the real analyzer does.
  void fail() => failureController.add(null);

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
  Future<void> dispose() async {
    await failureController.close();
    await controller.close();
    await super.dispose();
  }

  /// Pushes one analyzed batch, as the worker would.
  void emit(List<double> levels) => controller.add(levels);
}
