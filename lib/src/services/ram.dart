import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// One system-memory reading as a 0-1 used fraction plus the byte totals the
/// fraction came from.
class RamSample extends Equatable {
  const RamSample({this.usedBytes, this.totalBytes, this.history = const []});

  /// Readings the sparkline keeps: 45 samples at the 1 Hz cadence.
  static const int capacity = 45;

  final int? usedBytes;
  final int? totalBytes;

  /// Up to [capacity] used fractions, oldest first; the newest equals
  /// [current].
  final List<double> history;

  double? get current {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) {
      return null;
    }
    return (used / total).clamp(0.0, 1.0);
  }

  RamSample append(double usage) {
    final next = <double>[...history, usage];
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    return RamSample(
      usedBytes: usedBytes,
      totalBytes: totalBytes,
      history: List.unmodifiable(next),
    );
  }

  @override
  List<Object?> get props => [usedBytes, totalBytes, history];

  Map<String, Object?> toJson() => {
    'current': current,
    'used_bytes': usedBytes,
    'total_bytes': totalBytes,
    'history': history,
  };

  static RamSample fromJson(Map<String, dynamic> json) => RamSample(
    usedBytes: (json['used_bytes'] as num?)?.toInt(),
    totalBytes: (json['total_bytes'] as num?)?.toInt(),
    history: [
      for (final value in json['history'] as List<dynamic>? ?? const [])
        (value as num).toDouble(),
    ],
  );
}

/// Parses the bytes available from `/proc/meminfo`.
///
/// `MemAvailable` is the kernel's estimate and matches what `free` reports.
/// The fallback is only for kernels that predate it; it is deliberately not
/// used when the key exists, even if the value is zero.
@visibleForTesting
({int total, int available})? parseMeminfo(String source) {
  final values = <String, int>{};
  for (final line in source.split('\n')) {
    final separator = line.indexOf(':');
    if (separator == -1) {
      continue;
    }
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim().split(RegExp(r'\s+'));
    final kilobytes = int.tryParse(value.first);
    if (kilobytes == null) {
      continue;
    }
    values[key] = kilobytes * 1024;
  }

  final total = values['MemTotal'];
  if (total == null || total <= 0) {
    return null;
  }

  var available = values['MemAvailable'];
  if (available == null) {
    final free = values['MemFree'];
    final buffers = values['Buffers'];
    final cached = values['Cached'];
    if (free == null || buffers == null || cached == null) {
      return null;
    }
    available =
        free +
        buffers +
        cached +
        (values['SReclaimable'] ?? 0) -
        (values['Shmem'] ?? 0);
  }

  return (total: total, available: available.clamp(0, total));
}

/// Reads aggregate memory use from `/proc/meminfo` at 1 Hz.
///
/// Unlike the CPU delta, the reading is absolute, so start and resume emit one
/// fresh sample immediately. A disabled or paused module holds no timer.
class RamSampler {
  RamSampler({
    this.interval = const Duration(seconds: 1),
    String meminfoPath = '/proc/meminfo',
  }) : _meminfoPath = meminfoPath;

  final Duration interval;
  final String _meminfoPath;

  /// `/proc/meminfo` is about 1.5 KB today; the buffer is reused for every
  /// read and leaves room for additional fields without reallocating.
  final Uint8List _buffer = Uint8List(8 * 1024);
  RamSample _latest = const RamSample();
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  final _controller = StreamController<RamSample>.broadcast();

  Stream<RamSample> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  /// Starts sampling. A paused start leaves the timer stopped so a module
  /// created while the seat is already idle does no periodic work.
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
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    if (!_running) {
      return;
    }
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
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  void _sample() {
    if (!_running || _paused || _disposed) {
      return;
    }
    final file = File(_meminfoPath);
    RandomAccessFile? opened;
    try {
      if (!file.existsSync()) {
        return;
      }
      opened = file.openSync();
      final read = opened.readIntoSync(_buffer);
      if (read <= 0) {
        return;
      }
      final parsed = parseMeminfo(String.fromCharCodes(_buffer, 0, read));
      if (parsed == null) {
        return;
      }
      _latest = RamSample(
        usedBytes: parsed.total - parsed.available,
        totalBytes: parsed.total,
        history: _latest.history,
      ).append((parsed.total - parsed.available) / parsed.total);
      _controller.add(_latest);
    } on FileSystemException {
      // A missing or unreadable meminfo leaves the last good reading in place;
      // the pill hides when the very first read never landed.
    } finally {
      opened?.closeSync();
    }
  }
}
