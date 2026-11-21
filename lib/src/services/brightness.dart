import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// One readable backlight from `/sys/class/backlight`.
///
/// [fraction] is the driver's stored level over its maximum. Zero is a valid
/// brightness; a missing or unreadable device is represented by a sample with
/// null fields, never by a synthetic zero.
class BrightnessSample extends Equatable {
  const BrightnessSample({
    this.current,
    this.max,
    this.actual,
    this.device,
    this.type,
    this.scale,
  });

  final int? current;
  final int? max;

  /// `actual_brightness` when the driver publishes it; informational only.
  final int? actual;

  /// Device directory name (`intel_backlight`, `amdgpu_bl0`, ...).
  final String? device;

  /// `firmware`, `platform`, `raw`, or null when the driver publishes none.
  final String? type;

  /// `unknown`, `linear`, or `non-linear`; informational only.
  final String? scale;

  bool get visible => fraction != null;

  double? get fraction {
    final maximum = max;
    final value = current;
    if (maximum == null || maximum <= 0 || value == null || value < 0) {
      return null;
    }
    return (value / maximum).clamp(0.0, 1.0);
  }

  int? get percent {
    final value = fraction;
    return value == null ? null : (value * 100).round();
  }

  @override
  List<Object?> get props => [current, max, actual, device, type, scale];

  Map<String, Object?> toJson() => {
    'current': current,
    'max': max,
    'actual': actual,
    'device': device,
    'type': type,
    'scale': scale,
    'percent': percent,
  };

  static BrightnessSample fromJson(Map<String, dynamic> json) =>
      BrightnessSample(
        current: (json['current'] as num?)?.toInt(),
        max: (json['max'] as num?)?.toInt(),
        actual: (json['actual'] as num?)?.toInt(),
        device: json['device'] as String?,
        type: json['type'] as String?,
        scale: json['scale'] as String?,
      );
}

class _BrightnessReading {
  const _BrightnessReading({
    required this.sample,
    required this.typeRank,
    required this.acpiRank,
  });

  final BrightnessSample sample;

  /// Firmware is preferred over platform, and platform over raw.
  final int typeRank;

  /// Within one type, a vendor device wins over the ACPI fallback duplicate.
  final int acpiRank;
}

/// Reads one backlight from sysfs.
///
/// Firmware interfaces are preferred over platform, and platform over raw;
/// within one type, `acpi_video*` loses to a vendor interface. Unreadable or
/// malformed devices are skipped ([BrightnessSample.current] stays null),
/// never coerced to zero.
class BrightnessSampler {
  BrightnessSampler({
    this.interval = const Duration(seconds: 1),
    String backlightRoot = '/sys/class/backlight',
  }) : _backlightRoot = backlightRoot;

  final Duration interval;
  final String _backlightRoot;

  /// Whether the machine publishes at least one usable backlight. Used by the
  /// settings availability probe without starting a sampler.
  static bool hasReadableDevice({
    String backlightRoot = '/sys/class/backlight',
  }) {
    return _read(backlightRoot) != null;
  }

  BrightnessSample _latest = const BrightnessSample();
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  final _controller = StreamController<BrightnessSample>.broadcast();

  Stream<BrightnessSample> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  @visibleForTesting
  bool get isActive => _running;

  /// Starts sampling. A paused start leaves the timer stopped so a module
  /// created while the seat is already idle does no periodic work.
  void start({bool paused = false}) {
    if (_disposed) {
      return;
    }
    if (_running) {
      if (paused) {
        pause();
      } else if (_paused) {
        resume();
      } else if (_timer == null) {
        // A previous scan found no device and stopped the timer; a repeated
        // start is a cheap re-probe.
        _sample();
      }
      return;
    }
    _running = true;
    _paused = paused;
    if (!_paused) {
      _sample();
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
  }

  /// Re-probes after a settings reload. A paused or stopped sampler ignores
  /// the request; its next resume owns the scan.
  void refresh() {
    if (!_running || _paused || _disposed) {
      return;
    }
    _sample();
  }

  void _schedule() {
    if (_disposed) {
      return;
    }
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
    final sample = _read(_backlightRoot);
    if (sample == null) {
      // Clear a previously visible pill when the device disappears, and stop
      // the timer: a missing backlight must not cost a scan every second.
      _timer?.cancel();
      _timer = null;
      if (_latest.current != null) {
        _latest = const BrightnessSample();
        _controller.add(_latest);
      }
      return;
    }
    // Re-emit only real changes; a static brightness must not rebuild the
    // pill once per second.
    if (sample != _latest) {
      _latest = sample;
      _controller.add(sample);
    }
    _schedule();
  }

  static BrightnessSample? _read(String root) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      return null;
    }
    final List<Directory> devices;
    try {
      devices =
          directory
              .listSync(followLinks: true)
              .whereType<Directory>()
              .toList(growable: false)
            ..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      return null;
    }

    _BrightnessReading? best;
    for (final device in devices) {
      final reading = _readOne(device);
      if (reading == null) {
        continue;
      }
      if (best == null || _compare(reading, best) < 0) {
        best = reading;
      }
    }
    return best?.sample;
  }

  static _BrightnessReading? _readOne(Directory device) {
    final currentRaw = _readInt(File('${device.path}/brightness'));
    final maxRaw = _readInt(File('${device.path}/max_brightness'));
    // Zero is a valid brightness; a non-positive or missing maximum is not a
    // usable device.
    if (currentRaw == null || currentRaw < 0 || maxRaw == null || maxRaw <= 0) {
      return null;
    }
    final current = currentRaw.clamp(0, maxRaw);
    final actualRaw = _readInt(File('${device.path}/actual_brightness'));
    final actual = actualRaw == null || actualRaw < 0
        ? null
        : actualRaw.clamp(0, maxRaw);
    final type = _readText(File('${device.path}/type'))?.trim().toLowerCase();
    final scale = _readText(File('${device.path}/scale'))?.trim().toLowerCase();
    final segments = device.path
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final name = segments.isEmpty ? device.path : segments.last;
    return _BrightnessReading(
      sample: BrightnessSample(
        current: current,
        max: maxRaw,
        actual: actual,
        device: name,
        type: type == null || type.isEmpty ? null : type,
        scale: scale == null || scale.isEmpty ? null : scale,
      ),
      typeRank: _typeRank(type),
      acpiRank: name.toLowerCase().startsWith('acpi_video') ? 1 : 0,
    );
  }

  static int _compare(_BrightnessReading left, _BrightnessReading right) {
    final type = left.typeRank.compareTo(right.typeRank);
    if (type != 0) {
      return type;
    }
    final acpi = left.acpiRank.compareTo(right.acpiRank);
    if (acpi != 0) {
      return acpi;
    }
    return (left.sample.device ?? '').compareTo(right.sample.device ?? '');
  }

  static int _typeRank(String? type) {
    return switch (type) {
      'firmware' => 0,
      'platform' => 1,
      'raw' => 2,
      _ => 3,
    };
  }

  static String? _readText(File file) {
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  static int? _readInt(File file) {
    final text = _readText(file);
    return text == null ? null : int.tryParse(text.trim());
  }
}
