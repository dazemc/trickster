import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class GpuLoad extends Equatable {
  const GpuLoad({
    required this.id,
    required this.label,
    this.usage,
    this.history = const <double>[],
  });

  /// Readings each sparkline keeps: 45 samples at the 1 Hz cadence.
  static const int capacity = 45;

  final String id;
  final String label;
  final double? usage;

  /// Up to [capacity] readings, oldest first; the newest equals [usage].
  final List<double> history;

  GpuLoad append(double usage) {
    final next = <double>[...history, usage];
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    return GpuLoad(
      id: id,
      label: label,
      usage: usage,
      history: List.unmodifiable(next),
    );
  }

  @override
  List<Object?> get props => [id, label, usage, history];

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'usage': usage,
    'history': history,
  };

  static GpuLoad fromJson(Map<String, dynamic> json) => GpuLoad(
    id: '${json['id']}',
    label: '${json['label']}',
    usage: (json['usage'] as num?)?.toDouble(),
    history: [
      for (final value in json['history'] as List<dynamic>? ?? const [])
        (value as num).toDouble(),
    ],
  );
}

/// Autodetects every GPU whose utilization is readable without spawning
/// processes: amdgpu publishes `gpu_busy_percent` under `/sys/class/drm`.
/// GPUs offering no such file (i915, nouveau, the NVIDIA proprietary driver)
/// simply do not appear.
class GpuSampler {
  GpuSampler({
    this.interval = const Duration(seconds: 1),
    String drmRoot = '/sys/class/drm',
  }) : _drmRoot = drmRoot;

  final Duration interval;
  final String _drmRoot;
  final Uint8List _buffer = Uint8List(256);
  List<_GpuDevice>? _devices;
  List<GpuLoad> _loads = const <GpuLoad>[];
  Timer? _timer;
  final _controller = StreamController<List<GpuLoad>>.broadcast();

  Stream<List<GpuLoad>> get snapshots => _controller.stream;

  void start() {
    _controller.add(sample());
    _timer = Timer.periodic(interval, (_) => _controller.add(sample()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  /// One synchronous pass over the discovered cards, appending each reading
  /// to the card's series. Exposed so tests (and any caller wanting the
  /// series without the periodic timer) can drive it directly.
  List<GpuLoad> sample() {
    _devices ??= _discover();
    final previous = <String, GpuLoad>{
      for (final load in _loads) load.id: load,
    };
    final next = <GpuLoad>[];
    for (final device in _devices!) {
      final usage = _busyPercent(device.busyFile);
      if (usage == null) {
        continue;
      }
      final prior = previous[device.id];
      next.add(
        prior == null
            ? GpuLoad(id: device.id, label: device.label).append(usage)
            : prior.append(usage),
      );
    }
    _loads = _disambiguate(next);
    return _loads;
  }

  List<_GpuDevice> _discover() {
    final root = Directory(_drmRoot);
    if (!root.existsSync()) {
      return const <_GpuDevice>[];
    }
    final devices = <_GpuDevice>[];
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (!_cardName.hasMatch(name)) {
          continue;
        }
        final device = '${entity.path}/device';
        final busyFile = File('$device/gpu_busy_percent');
        if (!busyFile.existsSync()) {
          continue;
        }
        devices.add(
          _GpuDevice(
            id: name,
            label: _vendorLabel(File('$device/vendor')),
            busyFile: busyFile,
          ),
        );
      }
    } on FileSystemException {
      return const <_GpuDevice>[];
    }
    devices.sort((a, b) => a.id.compareTo(b.id));
    return devices;
  }

  static final RegExp _cardName = RegExp(r'^card\d+$');

  String _vendorLabel(File file) {
    final vendor = _readText(file)?.trim();
    return switch (vendor) {
      '0x1002' => 'AMD',
      '0x10de' => 'NV',
      '0x8086' => 'INT',
      _ => 'GPU',
    };
  }

  double? _busyPercent(File file) {
    final percent = int.tryParse(_readText(file)?.trim() ?? '');
    if (percent == null) {
      return null;
    }
    return (percent / 100.0).clamp(0.0, 1.0);
  }

  String? _readText(File file) {
    try {
      final opened = file.openSync();
      try {
        final read = opened.readIntoSync(_buffer);
        if (read <= 0) {
          return null;
        }
        return String.fromCharCodes(_buffer.sublist(0, read));
      } finally {
        opened.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  /// Suffixes duplicated vendor tags with a stable index (`AMD0`, `AMD1`) so
  /// identical cards keep distinguishable pills; unique tags stay untouched.
  static List<GpuLoad> _disambiguate(List<GpuLoad> loads) {
    final counts = <String, int>{};
    for (final load in loads) {
      counts[load.label] = (counts[load.label] ?? 0) + 1;
    }
    final seen = <String, int>{};
    return <GpuLoad>[
      for (final load in loads)
        if (counts[load.label]! > 1)
          GpuLoad(
            id: load.id,
            label:
                '${load.label}${seen[load.label] = (seen[load.label] ?? -1) + 1}',
            usage: load.usage,
            history: load.history,
          )
        else
          load,
    ];
  }
}

class _GpuDevice {
  const _GpuDevice({
    required this.id,
    required this.label,
    required this.busyFile,
  });

  final String id;
  final String label;
  final File busyFile;
}
