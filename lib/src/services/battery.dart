import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Power state read from sysfs `status`.
enum BatteryState { unknown, charging, discharging, full, notCharging }

class BatteryStatus extends Equatable {
  const BatteryStatus({
    this.capacity,
    this.charging = false,
    this.state = BatteryState.unknown,
    this.energyNow,
    this.energyFull,
    this.powerNow,
    this.chargeNow,
    this.chargeFull,
    this.currentNow,
    this.timeToEmpty,
    this.timeToFull,
  });

  final int? capacity;
  final bool charging;
  final BatteryState state;

  /// Raw sysfs counters in their native units: `energy_now`/`energy_full` are
  /// µWh, `power_now` is µW, `charge_now`/`charge_full` are µAh, and
  /// `current_now` is µA.
  final int? energyNow;
  final int? energyFull;
  final int? powerNow;
  final int? chargeNow;
  final int? chargeFull;
  final int? currentNow;

  /// Rounded to the minute. Null when the state or readings cannot yield a
  /// truthful estimate.
  final Duration? timeToEmpty;
  final Duration? timeToFull;

  // Raw counters are provenance, not displayed state: a sample whose rounded
  // remaining time did not change is deduplicated by the sampler.
  @override
  List<Object?> get props => [
    capacity,
    charging,
    state,
    timeToEmpty,
    timeToFull,
  ];

  Map<String, Object?> toJson() => {
    'capacity': capacity,
    'charging': charging,
    'state': state.name,
    'energyNow': energyNow,
    'energyFull': energyFull,
    'powerNow': powerNow,
    'chargeNow': chargeNow,
    'chargeFull': chargeFull,
    'currentNow': currentNow,
    'timeToEmptySeconds': timeToEmpty?.inSeconds,
    'timeToFullSeconds': timeToFull?.inSeconds,
  };

  static BatteryStatus fromJson(Map<String, dynamic> json) {
    final charging = (json['charging'] as bool?) ?? false;
    return BatteryStatus(
      capacity: (json['capacity'] as num?)?.toInt(),
      charging: charging,
      state: _stateFromJson(json['state'], charging),
      energyNow: (json['energyNow'] as num?)?.toInt(),
      energyFull: (json['energyFull'] as num?)?.toInt(),
      powerNow: (json['powerNow'] as num?)?.toInt(),
      chargeNow: (json['chargeNow'] as num?)?.toInt(),
      chargeFull: (json['chargeFull'] as num?)?.toInt(),
      currentNow: (json['currentNow'] as num?)?.toInt(),
      timeToEmpty: _durationFromSeconds(json['timeToEmptySeconds']),
      timeToFull: _durationFromSeconds(json['timeToFullSeconds']),
    );
  }

  static BatteryState _stateFromJson(Object? value, bool charging) {
    if (value is String) {
      for (final state in BatteryState.values) {
        if (state.name == value) {
          return state;
        }
      }
    }
    // Documents written before the state field existed still carry the
    // charging boolean; preserve the one fact they encoded.
    return charging ? BatteryState.charging : BatteryState.unknown;
  }

  static Duration? _durationFromSeconds(Object? value) {
    final seconds = (value as num?)?.toInt();
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }
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
        final capacity = int.tryParse(
          (await capacityFile.readAsString()).trim(),
        );
        final state = _stateFromStatus(
          await _readText('${entity.path}/status'),
        );
        final energyNow = await _readInt('${entity.path}/energy_now');
        final energyFull = await _readInt('${entity.path}/energy_full');
        final powerNow = await _readInt('${entity.path}/power_now');
        final chargeNow = await _readInt('${entity.path}/charge_now');
        final chargeFull = await _readInt('${entity.path}/charge_full');
        final currentNow = await _readInt('${entity.path}/current_now');
        final times = _batteryTimes(
          state,
          energyNow,
          energyFull,
          powerNow,
          chargeNow,
          chargeFull,
          currentNow,
        );
        return BatteryStatus(
          capacity: capacity,
          charging:
              state == BatteryState.charging || state == BatteryState.full,
          state: state,
          energyNow: energyNow,
          energyFull: energyFull,
          powerNow: powerNow,
          chargeNow: chargeNow,
          chargeFull: chargeFull,
          currentNow: currentNow,
          timeToEmpty: times.toEmpty,
          timeToFull: times.toFull,
        );
      }
    } on Object {
      return const BatteryStatus();
    }
    return const BatteryStatus();
  }

  Future<String> _readText(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    return (await file.readAsString()).trim();
  }

  Future<int?> _readInt(String path) async {
    final text = await _readText(path);
    return text.isEmpty ? null : int.tryParse(text);
  }

  BatteryState _stateFromStatus(String status) => switch (status) {
    'Charging' => BatteryState.charging,
    'Discharging' => BatteryState.discharging,
    'Full' => BatteryState.full,
    'Not charging' => BatteryState.notCharging,
    _ => BatteryState.unknown,
  };

  ({Duration? toEmpty, Duration? toFull}) _batteryTimes(
    BatteryState state,
    int? energyNow,
    int? energyFull,
    int? powerNow,
    int? chargeNow,
    int? chargeFull,
    int? currentNow,
  ) {
    if (state == BatteryState.charging) {
      final remainingEnergy = _remaining(energyFull, energyNow);
      final remainingCharge = _remaining(chargeFull, chargeNow);
      return (
        toEmpty: null,
        toFull:
            _timeFrom(remainingEnergy, powerNow) ??
            _timeFrom(remainingCharge, currentNow),
      );
    }
    if (state == BatteryState.discharging) {
      return (
        toEmpty:
            _timeFrom(energyNow, powerNow) ?? _timeFrom(chargeNow, currentNow),
        toFull: null,
      );
    }
    return (toEmpty: null, toFull: null);
  }

  int? _remaining(int? full, int? now) {
    if (full == null || now == null) {
      return null;
    }
    final remaining = full - now;
    return remaining > 0 ? remaining : null;
  }

  Duration? _timeFrom(int? amount, int? rate) {
    if (amount == null || rate == null || amount <= 0 || rate == 0) {
      return null;
    }
    // energy_now/power_now and charge_now/current_now share the same unit
    // ratio, so the quotient is hours for either pair. Some drivers report a
    // signed rate; the magnitude is the drain or charge speed.
    final minutes = ((amount / rate.abs()) * 60).round();
    return Duration(minutes: minutes > 0 ? minutes : 1);
  }
}
