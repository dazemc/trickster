import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/nvidia.dart';

class GpuLoad extends Equatable {
  const GpuLoad({
    required this.id,
    required this.label,
    this.name,
    this.usage,
    this.history = const <double>[],
  });

  /// Readings each sparkline keeps: 45 samples at the 1 Hz cadence.
  static const int capacity = 45;

  final String id;

  /// Caption shown by the meter: a vendor tag (or [genericLabel]), with a
  /// 0-based suffix when duplicate.
  final String label;

  /// Caption used when the device publishes no vendor tag.
  static const String genericLabel = 'GPU';

  /// Queried device name, or null when the driver publishes none. The meter
  /// caption stays [label] until a module option selects the device name.
  final String? name;

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
      name: name,
      usage: usage,
      history: List.unmodifiable(next),
    );
  }

  @override
  List<Object?> get props => [id, label, name, usage, history];

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'name': name,
    'usage': usage,
    'history': history,
  };

  static GpuLoad fromJson(Map<String, dynamic> json) => GpuLoad(
    id: '${json['id']}',
    label: '${json['label']}',
    name: json['name'] as String?,
    usage: (json['usage'] as num?)?.toDouble(),
    history: [
      for (final value in json['history'] as List<dynamic>? ?? const [])
        (value as num).toDouble(),
    ],
  );
}

List<Map<String, Object?>> gpuLoadsToJson(List<GpuLoad> loads) =>
    loads.map((load) => load.toJson()).toList(growable: false);

List<GpuLoad> gpuLoadsFromJson(List<dynamic> json) => json
    .whereType<Map<String, dynamic>>()
    .map(GpuLoad.fromJson)
    .toList(growable: false);

/// Bloc state for the GPU list. A bare `List` compares by identity, so the
/// wrapper exists to give the bloc value semantics — and a JSON shape for
/// the future `tricksterctl status` dump.
class GpuState extends Equatable {
  const GpuState([this.loads = const []]);

  final List<GpuLoad> loads;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the list (each GpuLoad is itself Equatable).
  @override
  List<Object?> get props => [...loads];

  Map<String, Object?> toJson() => {'gpus': gpuLoadsToJson(loads)};

  static GpuState fromJson(Map<String, dynamic> json) =>
      GpuState(gpuLoadsFromJson((json['gpus'] as List?) ?? const []));
}

/// Autodetects GPU utilization without spawning sampling processes: amdgpu
/// publishes `gpu_busy_percent` under `/sys/class/drm`; the NVIDIA proprietary
/// driver is read over NVML on a persistent worker isolate. GPUs offering
/// neither (i915, nouveau) simply do not appear, and NVML is only consulted
/// when the proprietary driver or a discovered NVIDIA card is present, so
/// AMD-only systems never load it.
class GpuSampler {
  GpuSampler({
    this.interval = const Duration(seconds: 1),
    String drmRoot = '/sys/class/drm',
    NvmlReader? nvml,
    String nvidiaDriverPath = '/proc/driver/nvidia/version',
    void Function(String message)? log,
  }) : _drmRoot = drmRoot,
       _nvml = nvml ?? NvmlReader(),
       _nvidiaDriverPath = nvidiaDriverPath,
       _log = log ?? _stderrLog;

  final Duration interval;
  final String _drmRoot;
  final NvmlReader _nvml;
  final String _nvidiaDriverPath;
  final void Function(String message) _log;
  var _nvidiaFailureLogged = false;
  final Uint8List _buffer = Uint8List(256);
  List<_GpuDevice>? _devices;
  List<File>? _nvidiaRuntimeStatusFiles;
  bool? _nvidiaDriverPresent;
  var _discoveredNvidia = false;
  List<GpuLoad> _loads = const <GpuLoad>[];
  Timer? _timer;
  var _sampling = false;
  final _controller = StreamController<List<GpuLoad>>.broadcast();

  Stream<List<GpuLoad>> get snapshots => _controller.stream;

  bool get _hasNvidia =>
      (_nvidiaDriverPresent ??= File(_nvidiaDriverPath).existsSync()) ||
      _discoveredNvidia;

  void start() {
    unawaited(_tick());
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _nvml.dispose();
    await _controller.close();
  }

  Future<void> _tick() async {
    if (_sampling) {
      return;
    }
    _sampling = true;
    try {
      _controller.add(await sample());
    } finally {
      _sampling = false;
    }
  }

  /// One pass over the discovered cards, appending each reading to the
  /// card's series. Exposed so tests (and any caller wanting the series
  /// without the periodic timer) can drive it directly.
  Future<List<GpuLoad>> sample() async {
    _devices ??= _discover();
    final reads = <({String id, String label, String? name, double usage})>[
      for (final device in _devices!)
        if (_busyPercent(device.busyFile) case final usage?)
          (id: device.id, label: device.label, name: null, usage: usage),
    ];
    if (_hasNvidia) {
      if (await _canReadNvidiaWithoutWake()) {
        final read = await _nvml.read();
        final error = read.error;
        if (error != null && !_nvidiaFailureLogged) {
          // One line per process, not one per sample: a driver update that
          // left the kernel module behind must not spam the log.
          _nvidiaFailureLogged = true;
          _log('trickster: NVIDIA GPU unavailable: $error');
        }
        for (final nvidia in read.samples) {
          final name = nvidia.name?.trim();
          reads.add((
            id: 'nvml${nvidia.index}',
            label: GpuLoad.genericLabel,
            name: name == null || name.isEmpty ? null : name,
            usage: nvidia.usage,
          ));
        }
      } else {
        for (
          var index = 0;
          index < _nvidiaRuntimeStatusFiles!.length;
          index += 1
        ) {
          reads.add((
            id: 'nvml$index',
            label: GpuLoad.genericLabel,
            name: null,
            usage: 0.0,
          ));
        }
      }
    }
    final previous = <String, GpuLoad>{
      for (final load in _loads) load.id: load,
    };
    final next = <GpuLoad>[
      for (final read in reads)
        (previous[read.id] ??
                GpuLoad(id: read.id, label: read.label, name: read.name))
            .append(read.usage),
    ];
    _loads = _disambiguate(next);
    return _loads;
  }

  List<_GpuDevice> _discover() {
    final root = Directory(_drmRoot);
    if (!root.existsSync()) {
      return const <_GpuDevice>[];
    }
    final devices = <_GpuDevice>[];
    final nvidiaRuntimeStatusFiles = <File>[];
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
        final vendor = _readText(File('$device/vendor'))?.trim();
        if (vendor == '0x10de') {
          _discoveredNvidia = true;
          final runtimeStatus = File('$device/power/runtime_status');
          if (runtimeStatus.existsSync()) {
            nvidiaRuntimeStatusFiles.add(runtimeStatus);
          }
        }
        final busyFile = File('$device/gpu_busy_percent');
        if (!busyFile.existsSync()) {
          continue;
        }
        devices.add(
          _GpuDevice(id: name, label: _vendorLabel(vendor), busyFile: busyFile),
        );
      }
    } on FileSystemException {
      _nvidiaRuntimeStatusFiles = const <File>[];
      return const <_GpuDevice>[];
    }
    _nvidiaRuntimeStatusFiles = nvidiaRuntimeStatusFiles;
    devices.sort((a, b) => a.id.compareTo(b.id));
    return devices;
  }

  /// NVML utilization queries power on a runtime-suspended dGPU. Leave hybrid
  /// graphics asleep until another workload activates them.
  Future<bool> _canReadNvidiaWithoutWake() async {
    final statusFiles = _nvidiaRuntimeStatusFiles;
    if (statusFiles == null || statusFiles.isEmpty) {
      // Desktop NVIDIA systems may not expose runtime PM through DRM. Keep
      // NVML available there because querying an always-on GPU cannot wake it.
      return true;
    }
    var suspended = false;
    for (final statusFile in statusFiles) {
      try {
        final status = (await statusFile.readAsString()).trim();
        if (status == 'suspended' ||
            status == 'suspending' ||
            status == 'resuming') {
          suspended = true;
        }
      } on FileSystemException {
        continue;
      }
    }
    return !suspended;
  }

  static final RegExp _cardName = RegExp(r'^card\d+$');

  String _vendorLabel(String? vendor) {
    return switch (vendor) {
      '0x1002' => 'AMD',
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
            name: load.name,
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

void _stderrLog(String message) => stderr.writeln(message);
