import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class CpuSample extends Equatable {
  const CpuSample(this.current, {this.history = const <double>[], this.label});

  /// Readings each sparkline keeps: 45 samples at the 1 Hz cadence.
  static const int capacity = 45;

  final double? current;

  /// Up to [capacity] readings, oldest first; the newest equals [current].
  final List<double> history;

  /// Device name from `/proc/cpuinfo`, or null before it is read.
  final String? label;

  CpuSample append(double usage) {
    final next = <double>[...history, usage];
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    return CpuSample(
      usage,
      history: List.unmodifiable(next),
      label: label,
    );
  }

  @override
  List<Object?> get props => [current, history, label];

  Map<String, Object?> toJson() => {
    'current': current,
    'history': history,
    'label': label,
  };

  static CpuSample fromJson(Map<String, dynamic> json) => CpuSample(
    (json['current'] as num?)?.toDouble(),
    history: [
      for (final value in json['history'] as List<dynamic>? ?? const [])
        (value as num).toDouble(),
    ],
    label: json['label'] as String?,
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

class CpuSampler {
  CpuSampler({
    this.interval = const Duration(seconds: 1),
    String cpuInfoPath = '/proc/cpuinfo',
  }) : _cpuInfoPath = cpuInfoPath;

  final Duration interval;
  final String _cpuInfoPath;
  final Uint8List _buffer = Uint8List(256);
  int? _idle;
  int? _total;
  CpuSample _latest = const CpuSample(null);
  String? _label;
  var _labelRead = false;
  Timer? _timer;
  final _controller = StreamController<CpuSample>.broadcast();

  Stream<CpuSample> get snapshots => _controller.stream;

  void start() {
    _latest = CpuSample(null, label: _deviceLabel());
    _sample();
    _timer = Timer.periodic(interval, (_) => _sample());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  String? _deviceLabel() {
    if (_labelRead) {
      return _label;
    }
    _labelRead = true;
    try {
      _label = parseCpuModelName(File(_cpuInfoPath).readAsStringSync());
    } on Object {
      _label = null;
    }
    return _label;
  }

  void _sample() {
    final file = File('/proc/stat');
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
      _latest = _latest.append(math.min(1.0, math.max(0.0, busy)));
      _controller.add(_latest);
    } finally {
      opened.closeSync();
    }
  }
}
