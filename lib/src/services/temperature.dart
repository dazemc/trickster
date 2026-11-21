import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// One hwmon temperature reading in Celsius with the sensor identity and a
/// rolling Celsius history.
class TemperatureSample extends Equatable {
  const TemperatureSample({
    this.celsius,
    this.label,
    this.chip,
    this.isCpu = false,
    this.history = const [],
  });

  /// Readings the sparkline keeps: 45 samples at the 1 Hz cadence.
  static const int capacity = 45;

  final double? celsius;

  /// `tempN_label`, or null when the driver publishes no label.
  final String? label;

  /// The hwmon chip name (`k10temp`, `coretemp`, `nvme`, ...).
  final String? chip;

  /// Whether the selected sensor belongs to a known CPU chip.
  final bool isCpu;

  /// Up to [capacity] Celsius readings, oldest first.
  final List<double> history;

  /// The history mapped onto the meter's 0–1, 0–100 °C scale.
  List<double> get meterHistory => [
    for (final value in history) (value / 100).clamp(0.0, 1.0),
  ];

  TemperatureSample append(
    double value, {
    String? label,
    String? chip,
    bool isCpu = false,
  }) {
    final next = <double>[...history, value];
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    return TemperatureSample(
      celsius: value,
      label: label,
      chip: chip,
      isCpu: isCpu,
      history: List.unmodifiable(next),
    );
  }

  @override
  List<Object?> get props => [celsius, label, chip, isCpu, history];

  Map<String, Object?> toJson() => {
    'current': celsius,
    'label': label,
    'chip': chip,
    'is_cpu': isCpu,
    'history': history,
  };

  static TemperatureSample fromJson(Map<String, dynamic> json) =>
      TemperatureSample(
        celsius: (json['current'] as num?)?.toDouble(),
        label: json['label'] as String?,
        chip: json['chip'] as String?,
        isCpu: json['is_cpu'] == true,
        history: [
          for (final value in json['history'] as List<dynamic>? ?? const [])
            (value as num).toDouble(),
        ],
      );
}

class _TemperatureReading {
  const _TemperatureReading({
    required this.celsius,
    required this.label,
    required this.chip,
    required this.cpuRank,
    required this.labelRank,
  });

  final double celsius;
  final String? label;
  final String? chip;
  final int? cpuRank;
  final int labelRank;

  bool get isCpu => cpuRank != null;
}

/// Reads one temperature from `/sys/class/hwmon`.
///
/// A sensor on a known CPU chip wins over the rest: `k10temp`/`zenpower` and
/// `coretemp` publish `Tctl`/`Tdie`/`Package`, which are the useful CPU
/// metrics. When no CPU sensor is readable, the hottest readable sensor is
/// used. Unreadable or malformed inputs are skipped, never coerced to zero.
class TemperatureSampler {
  TemperatureSampler({
    this.interval = const Duration(seconds: 1),
    String hwmonRoot = '/sys/class/hwmon',
  }) : _hwmonRoot = hwmonRoot;

  final Duration interval;
  final String _hwmonRoot;

  static const Set<String> _cpuChips = {'k10temp', 'coretemp', 'zenpower'};
  static final RegExp _temperatureInput = RegExp(r'^temp(\d+)_input$');

  TemperatureSample _latest = const TemperatureSample();
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  final _controller = StreamController<TemperatureSample>.broadcast();

  Stream<TemperatureSample> get snapshots => _controller.stream;

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
    final reading = _scan();
    if (reading == null) {
      // Clear a previously visible pill when the sensor disappears; a bar
      // that never had a reading keeps its initial null state.
      if (_latest.celsius != null) {
        _latest = TemperatureSample(history: _latest.history);
        _controller.add(_latest);
      }
      return;
    }
    _latest =
        TemperatureSample(
          label: reading.label,
          chip: reading.chip,
          isCpu: reading.isCpu,
          history: _latest.history,
        ).append(
          reading.celsius,
          label: reading.label,
          chip: reading.chip,
          isCpu: reading.isCpu,
        );
    _controller.add(_latest);
  }

  _TemperatureReading? _scan() {
    final root = Directory(_hwmonRoot);
    if (!root.existsSync()) {
      return null;
    }
    final readings = <_TemperatureReading>[];
    final List<Directory> directories;
    try {
      directories =
          root
              .listSync(followLinks: true)
              .whereType<Directory>()
              .toList(growable: false)
            ..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      return null;
    }
    for (final directory in directories) {
      try {
        final chip = _readText(File('${directory.path}/name'))?.trim();
        final inputs = <({int index, File file})>[];
        for (final entity in directory.listSync(followLinks: true)) {
          if (entity is! File) {
            continue;
          }
          final name = entity.uri.pathSegments.last;
          final match = _temperatureInput.firstMatch(name);
          if (match == null) {
            continue;
          }
          inputs.add((index: int.parse(match.group(1)!), file: entity));
        }
        inputs.sort((a, b) => a.index.compareTo(b.index));
        for (final input in inputs) {
          final raw = int.tryParse(_readText(input.file)?.trim() ?? '');
          if (raw == null) {
            continue;
          }
          final celsius = raw / 1000.0;
          final label = _readText(
            File('${directory.path}/temp${input.index}_label'),
          )?.trim();
          readings.add(
            _TemperatureReading(
              celsius: celsius,
              label: label == null || label.isEmpty ? null : label,
              chip: chip == null || chip.isEmpty ? null : chip,
              cpuRank: _cpuChipRank(chip),
              labelRank: _cpuLabelRank(label),
            ),
          );
        }
      } on FileSystemException {
        // One unreadable driver directory must not hide the others.
        continue;
      }
    }
    return _select(readings);
  }

  _TemperatureReading? _select(List<_TemperatureReading> readings) {
    _TemperatureReading? best;
    for (final reading in readings) {
      if (best == null) {
        best = reading;
        continue;
      }
      if (reading.isCpu != best.isCpu) {
        if (reading.isCpu) {
          best = reading;
        }
        continue;
      }
      if (reading.isCpu) {
        final chipComparison = reading.cpuRank!.compareTo(best.cpuRank!);
        if (chipComparison < 0) {
          best = reading;
          continue;
        }
        if (chipComparison > 0) {
          continue;
        }
        final labelComparison = reading.labelRank.compareTo(best.labelRank);
        if (labelComparison < 0) {
          best = reading;
          continue;
        }
        if (labelComparison > 0) {
          continue;
        }
      }
      if (reading.celsius > best.celsius) {
        best = reading;
      }
    }
    return best;
  }

  static int? _cpuChipRank(String? chip) {
    final name = chip?.toLowerCase();
    if (name == null || !_cpuChips.contains(name)) {
      return null;
    }
    return switch (name) {
      'k10temp' => 0,
      'coretemp' => 1,
      'zenpower' => 2,
      _ => null,
    };
  }

  static int _cpuLabelRank(String? label) {
    final name = label?.toLowerCase() ?? '';
    if (name.contains('tctl')) {
      return 0;
    }
    if (name.contains('tdie')) {
      return 1;
    }
    if (name.contains('package')) {
      return 2;
    }
    return 3;
  }

  static String? _readText(File file) {
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }
}
