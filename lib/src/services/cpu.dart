import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class CpuSample extends Equatable {
  const CpuSample(this.current);

  final double? current;

  @override
  List<Object?> get props => [current];

  Map<String, Object?> toJson() => {'current': current};

  static CpuSample fromJson(Map<String, dynamic> json) =>
      CpuSample((json['current'] as num?)?.toDouble());
}

class CpuSampler {
  CpuSampler({this.interval = const Duration(seconds: 1)});

  final Duration interval;
  final Uint8List _buffer = Uint8List(256);
  int? _idle;
  int? _total;
  Timer? _timer;
  final _controller = StreamController<CpuSample>.broadcast();

  Stream<CpuSample> get snapshots => _controller.stream;

  void start() {
    _sample();
    _timer = Timer.periodic(interval, (_) => _sample());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
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
      _controller.add(CpuSample(math.min(1.0, math.max(0.0, busy))));
    } finally {
      opened.closeSync();
    }
  }
}
