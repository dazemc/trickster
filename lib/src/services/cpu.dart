import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// One `/proc/loadavg` reading with the online CPU count used to normalize it.
class LoadAverage extends Equatable {
  const LoadAverage({
    required this.load1,
    required this.load5,
    required this.load15,
    required this.onlineCores,
  });

  final double load1;
  final double load5;
  final double load15;
  final int onlineCores;

  double get load1Fraction => load1 / onlineCores;
  double get load5Fraction => load5 / onlineCores;
  double get load15Fraction => load15 / onlineCores;

  @override
  List<Object?> get props => [load1, load5, load15, onlineCores];

  Map<String, Object?> toJson() => {
    'load1': load1,
    'load5': load5,
    'load15': load15,
    'online_cores': onlineCores,
  };

  static LoadAverage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final load1 = (json['load1'] as num?)?.toDouble();
    final load5 = (json['load5'] as num?)?.toDouble();
    final load15 = (json['load15'] as num?)?.toDouble();
    final onlineCores = (json['online_cores'] as num?)?.toInt();
    if (load1 == null ||
        load5 == null ||
        load15 == null ||
        onlineCores == null ||
        onlineCores <= 0 ||
        !load1.isFinite ||
        !load5.isFinite ||
        !load15.isFinite ||
        load1 < 0 ||
        load5 < 0 ||
        load15 < 0) {
      return null;
    }
    return LoadAverage(
      load1: load1,
      load5: load5,
      load15: load15,
      onlineCores: onlineCores,
    );
  }
}

class CpuSample extends Equatable {
  const CpuSample(
    this.current, {
    this.history = const <double>[],
    this.name,
    this.loadAverage,
  });

  /// Readings each sparkline keeps: 45 samples at the 1 Hz cadence.
  static const int capacity = 45;

  final double? current;

  /// Up to [capacity] readings, oldest first; the newest equals [current].
  final List<double> history;

  /// Device name from `/proc/cpuinfo`, or null before it is read. The meter
  /// caption stays the generic `CPU` tag until a module option selects it.
  final String? name;

  /// The latest `/proc/loadavg` reading, or null before it is available.
  final LoadAverage? loadAverage;

  CpuSample append(double usage, {LoadAverage? loadAverage}) {
    final next = <double>[...history, usage];
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    return CpuSample(
      usage,
      history: List.unmodifiable(next),
      name: name,
      loadAverage: loadAverage ?? this.loadAverage,
    );
  }

  @override
  List<Object?> get props => [current, history, name, loadAverage];

  Map<String, Object?> toJson() => {
    'current': current,
    'history': history,
    'name': name,
    'load_average': loadAverage?.toJson(),
  };

  static CpuSample fromJson(Map<String, dynamic> json) => CpuSample(
    (json['current'] as num?)?.toDouble(),
    history: [
      for (final value in json['history'] as List<dynamic>? ?? const [])
        (value as num).toDouble(),
    ],
    name: json['name'] as String?,
    loadAverage: LoadAverage.fromJson(json['load_average']),
  );
}

/// Reads the first `model name` line from `/proc/cpuinfo`. Returns null when
/// the architecture publishes no such line, so the pill can fall back to a
/// generic caption.
@visibleForTesting
String? parseCpuModelName(String cpuInfo) {
  for (final line in cpuInfo.split('\n')) {
    final separator = line.indexOf(':');
    if (separator == -1) {
      continue;
    }
    if (line.substring(0, separator).trim() != 'model name') {
      continue;
    }
    final name = line.substring(separator + 1).trim();
    if (name.isNotEmpty) {
      return name;
    }
  }
  return null;
}

/// Parses the three load averages from `/proc/loadavg`. The trailing runnable
/// and last-PID fields are ignored.
@visibleForTesting
({double load1, double load5, double load15})? parseLoadAverage(String source) {
  final parts = source.trim().split(RegExp(r'\s+'));
  if (parts.length < 3) {
    return null;
  }
  final load1 = double.tryParse(parts[0]);
  final load5 = double.tryParse(parts[1]);
  final load15 = double.tryParse(parts[2]);
  if (load1 == null ||
      load5 == null ||
      load15 == null ||
      !load1.isFinite ||
      !load5.isFinite ||
      !load15.isFinite ||
      load1 < 0 ||
      load5 < 0 ||
      load15 < 0) {
    return null;
  }
  return (load1: load1, load5: load5, load15: load15);
}

/// Counts the CPUs in a `/sys/devices/system/cpu/online` list such as
/// `0-15` or `0-3,8-11`. Ranges are counted arithmetically, never expanded.
@visibleForTesting
int? parseOnlineCpuCount(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  var count = 0;
  for (final token in trimmed.split(',')) {
    final range = token.trim().split('-');
    if (range.isEmpty || range.length > 2) {
      return null;
    }
    final start = int.tryParse(range[0].trim());
    final end = range.length == 1 ? start : int.tryParse(range[1].trim());
    if (start == null || end == null || start < 0 || end < start) {
      return null;
    }
    count += end - start + 1;
  }
  return count > 0 ? count : null;
}

class CpuSampler {
  CpuSampler({
    this.interval = const Duration(seconds: 1),
    this.resumePrime = const Duration(milliseconds: 100),
    String cpuInfoPath = '/proc/cpuinfo',
    String statPath = '/proc/stat',
    String loadavgPath = '/proc/loadavg',
    String onlineCpusPath = '/sys/devices/system/cpu/online',
  }) : _cpuInfoPath = cpuInfoPath,
       _statPath = statPath,
       _loadavgPath = loadavgPath,
       _onlineCpusPath = onlineCpusPath;

  final Duration interval;

  /// Short window used to take a fresh post-resume reading. The first read
  /// after idle is only a baseline, so the reported value reflects recent
  /// load instead of the whole idle interval.
  final Duration resumePrime;
  final String _cpuInfoPath;
  final String _statPath;
  final String _loadavgPath;
  final String _onlineCpusPath;
  final Uint8List _buffer = Uint8List(256);
  final Uint8List _loadavgBuffer = Uint8List(128);
  int? _idle;
  int? _total;
  int? _onlineCores;
  CpuSample _latest = const CpuSample(null);
  String? _name;
  var _nameRead = false;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  Timer? _timer;
  final _controller = StreamController<CpuSample>.broadcast();

  Stream<CpuSample> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  /// Starts sampling. A paused start takes the baseline but leaves the timer
  /// stopped so a module created while the seat is already idle does not
  /// begin periodic work.
  void start({bool paused = false}) {
    if (_running) {
      if (paused) {
        pause();
      } else {
        resume();
      }
      return;
    }
    _running = true;
    _latest = CpuSample(null, name: _deviceName());
    _paused = paused;
    if (!_paused) {
      _sample();
      _schedule();
    }
  }

  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;
    _timer?.cancel();
    _timer = null;
    // Discard the pre-idle counters: a delta spanning the idle window is not
    // a recent-load reading.
    _idle = null;
    _total = null;
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    if (!_running) {
      return;
    }
    // A resume can follow CPU hotplug; re-read the online count once.
    _onlineCores = null;
    _primeAfterIdle();
  }

  void _primeAfterIdle() {
    _idle = null;
    _total = null;
    _sample();
    _timer = Timer(resumePrime, () {
      _timer = null;
      if (_paused || !_running) {
        return;
      }
      _sample();
      _schedule();
    });
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
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  String? _deviceName() {
    if (_nameRead) {
      return _name;
    }
    _nameRead = true;
    try {
      _name = parseCpuModelName(File(_cpuInfoPath).readAsStringSync());
    } on Object {
      _name = null;
    }
    return _name;
  }

  int? _readOnlineCores() {
    try {
      return parseOnlineCpuCount(File(_onlineCpusPath).readAsStringSync());
    } on Object {
      return null;
    }
  }

  ({double load1, double load5, double load15})? _readLoadAverage() {
    final file = File(_loadavgPath);
    RandomAccessFile? opened;
    try {
      if (!file.existsSync()) {
        return null;
      }
      opened = file.openSync();
      final read = opened.readIntoSync(_loadavgBuffer);
      if (read <= 0) {
        return null;
      }
      return parseLoadAverage(String.fromCharCodes(_loadavgBuffer, 0, read));
    } on Object {
      return null;
    } finally {
      opened?.closeSync();
    }
  }

  void _sample() {
    final file = File(_statPath);
    if (!file.existsSync()) {
      return;
    }
    final opened = file.openSync();
    try {
      final read = opened.readIntoSync(_buffer);
      if (read <= 0) {
        return;
      }
      final line = String.fromCharCodes(_buffer.sublist(0, read));
      final end = line.indexOf('\n');
      final first = end == -1 ? line : line.substring(0, end);
      final parts = first.split(RegExp(r'\s+'));
      if (parts.length < 5 || parts.first != 'cpu') {
        return;
      }
      final idle = int.parse(parts[4]);
      var total = 0;
      for (var i = 1; i < parts.length; i++) {
        total += int.parse(parts[i]);
      }
      final previousIdle = _idle;
      final previousTotal = _total;
      _idle = idle;
      _total = total;
      if (previousIdle == null || previousTotal == null) {
        return;
      }
      final idleDelta = idle - previousIdle;
      final totalDelta = total - previousTotal;
      if (totalDelta <= 0) {
        return;
      }
      final busy = 1.0 - (idleDelta / totalDelta);
      final cores = _onlineCores ??= _readOnlineCores();
      final parsedLoad = _readLoadAverage();
      final loadAverage = cores == null || parsedLoad == null
          ? null
          : LoadAverage(
              load1: parsedLoad.load1,
              load5: parsedLoad.load5,
              load15: parsedLoad.load15,
              onlineCores: cores,
            );
      _latest = _latest.append(
        math.min(1.0, math.max(0.0, busy)),
        loadAverage: loadAverage,
      );
      _controller.add(_latest);
    } finally {
      opened.closeSync();
    }
  }
}
