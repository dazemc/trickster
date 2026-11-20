import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class BatteryStatus extends Equatable {
  const BatteryStatus({this.capacity, this.charging = false});

  final int? capacity;
  final bool charging;

  @override
  List<Object?> get props => [capacity, charging];

  Map<String, Object?> toJson() => {'capacity': capacity, 'charging': charging};

  static BatteryStatus fromJson(Map<String, dynamic> json) => BatteryStatus(
    capacity: (json['capacity'] as num?)?.toInt(),
    charging: (json['charging'] as bool?) ?? false,
  );
}

class BatterySampler {
  BatterySampler({
    this.interval = const Duration(seconds: 5),
    Directory? root,
    Future<BatteryStatus> Function()? readStatus,
  }) : _root = root ?? Directory('/sys/class/power_supply'),
       _readStatusOverride = readStatus;

  final Duration interval;
  final Directory _root;
  final Future<BatteryStatus> Function()? _readStatusOverride;
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  var _generation = 0;
  var _sampling = false;
  var _resample = false;
  BatteryStatus? _lastStatus;
  final _controller = StreamController<BatteryStatus>.broadcast();

  Stream<BatteryStatus> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  /// Starts sampling. A paused start leaves the timer stopped so a module
  /// created while the seat is already idle does no periodic work.
  void start({bool paused = false}) {
    if (_disposed) {
      return;
    }
    if (_running) {
      if (paused) {
        pause();
      } else {
        resume();
      }
      return;
    }
    _running = true;
    _paused = paused;
    if (!_paused) {
      unawaited(_sample());
      _schedule();
    }
  }

  void pause() {
    if (!_running || _paused) {
      return;
    }
    _paused = true;
    _generation += 1;
    _resample = false;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (!_running || !_paused || _disposed) {
      return;
    }
    _paused = false;
    _generation += 1;
    unawaited(_sample());
    _schedule();
  }

  void _schedule() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(_sample()));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _paused = true;
    _resample = false;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  Future<void> _sample() async {
    if (_disposed || _paused || _controller.isClosed) {
      return;
    }
    if (_sampling) {
      _resample = true;
      return;
    }
    _sampling = true;
    final generation = _generation;
    try {
      final status = await (_readStatusOverride?.call() ?? _readStatus());
      // A pause or dispose between the read and the emit must not publish the
      // previous generation's sample.
      if (generation != _generation ||
          _paused ||
          _disposed ||
          _controller.isClosed) {
        return;
      }
      if (status == _lastStatus) {
        return;
      }
      _lastStatus = status;
      _controller.add(status);
    } finally {
      _sampling = false;
      if (_resample) {
        _resample = false;
        if (!_paused && !_disposed && !_controller.isClosed) {
          unawaited(_sample());
        }
      }
    }
  }

  Future<BatteryStatus> _readStatus() async {
    try {
      if (!await _root.exists()) {
        return const BatteryStatus();
      }
      await for (final entity in _root.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (!name.startsWith('BAT')) {
          continue;
        }
        final capacityFile = File('${entity.path}/capacity');
        if (!await capacityFile.exists()) {
          continue;
        }
        final statusFile = File('${entity.path}/status');
        final capacity = int.tryParse(
          (await capacityFile.readAsString()).trim(),
        );
        final status = await statusFile.exists()
            ? (await statusFile.readAsString()).trim()
            : '';
        return BatteryStatus(
          capacity: capacity,
          charging: status == 'Charging' || status == 'Full',
        );
      }
    } on Object {
      return const BatteryStatus();
    }
    return const BatteryStatus();
  }
}
