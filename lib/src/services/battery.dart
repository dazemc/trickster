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
  BatterySampler({this.interval = const Duration(seconds: 5), Directory? root})
    : _root = root ?? Directory('/sys/class/power_supply');

  final Duration interval;
  final Directory _root;
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  var _generation = 0;
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
      _sample();
      _schedule();
    }
  }

  void pause() {
    if (!_running || _paused) {
      return;
    }
    _paused = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (!_running || !_paused || _disposed) {
      return;
    }
    _paused = false;
    _generation += 1;
    _sample();
    _schedule();
  }

  void _schedule() {
    _timer ??= Timer.periodic(interval, (_) => _sample());
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _paused = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  void _sample() {
    if (_disposed || _paused || _controller.isClosed) {
      return;
    }
    final generation = _generation;
    final status = _readStatus();
    // A pause or dispose between the read and the emit must not publish the
    // previous generation's sample.
    if (generation != _generation ||
        _paused ||
        _disposed ||
        _controller.isClosed) {
      return;
    }
    _controller.add(status);
  }

  BatteryStatus _readStatus() {
    if (!_root.existsSync()) {
      return const BatteryStatus();
    }
    for (final entity in _root.listSync()) {
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
      final statusFile = File('${entity.path}/status');
      if (!capacityFile.existsSync()) {
        continue;
      }
      final capacity = int.tryParse(capacityFile.readAsStringSync().trim());
      final status = statusFile.existsSync()
          ? statusFile.readAsStringSync().trim()
          : '';
      return BatteryStatus(
        capacity: capacity,
        charging: status == 'Charging' || status == 'Full',
      );
    }
    return const BatteryStatus();
  }
}
