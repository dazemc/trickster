import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:trickster/src/services/nvidia.dart';

class GpuLoad extends Equatable {
  const GpuLoad({
    required this.id,
    required this.label,
    this.name,
    this.usage,
    this.history = const <double>[],
    this.memoryUsedBytes,
    this.memoryTotalBytes,
    this.memoryHistory = const <double>[],
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

  /// Dedicated VRAM in use and total, or null when the device publishes no
  /// memory or the read was not requested.
  final int? memoryUsedBytes;
  final int? memoryTotalBytes;

  /// Up to [capacity] memory-used fractions, oldest first.
  final List<double> memoryHistory;

  double? get memoryFraction {
    final used = memoryUsedBytes;
    final total = memoryTotalBytes;
    if (used == null || total == null || total <= 0) {
      return null;
    }
    return (used / total).clamp(0.0, 1.0);
  }

  GpuLoad append(double? usage, {int? memoryUsedBytes, int? memoryTotalBytes}) {
    final next = <double>[...history];
    if (usage != null) {
      next.add(usage);
      if (next.length > capacity) {
        next.removeRange(0, next.length - capacity);
      }
    }
    final nextMemory = <double>[...memoryHistory];
    final memoryFraction =
        (memoryUsedBytes != null &&
            memoryTotalBytes != null &&
            memoryTotalBytes > 0)
        ? (memoryUsedBytes / memoryTotalBytes).clamp(0.0, 1.0)
        : null;
    if (memoryFraction != null) {
      nextMemory.add(memoryFraction);
      if (nextMemory.length > capacity) {
        nextMemory.removeRange(0, nextMemory.length - capacity);
      }
    }
    return GpuLoad(
      id: id,
      label: label,
      name: name,
      usage: usage,
      history: usage == null ? history : List.unmodifiable(next),
      memoryUsedBytes: memoryUsedBytes,
      memoryTotalBytes: memoryTotalBytes,
      memoryHistory: memoryFraction == null
          ? memoryHistory
          : List.unmodifiable(nextMemory),
    );
  }

  @override
  List<Object?> get props => [
    id,
    label,
    name,
    usage,
    history,
    memoryUsedBytes,
    memoryTotalBytes,
    memoryHistory,
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'name': name,
    'usage': usage,
    'history': history,
    'memory_used_bytes': memoryUsedBytes,
    'memory_total_bytes': memoryTotalBytes,
    'memory_history': memoryHistory,
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
    memoryUsedBytes: (json['memory_used_bytes'] as num?)?.toInt(),
    memoryTotalBytes: (json['memory_total_bytes'] as num?)?.toInt(),
    memoryHistory: [
      for (final value in json['memory_history'] as List<dynamic>? ?? const [])
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

/// Autodetects GPU utilization and dedicated VRAM without spawning sampling
/// processes: amdgpu/i915 expose `gpu_busy_percent` and `mem_info_vram_*`
/// under `/sys/class/drm`, Xe exposes `tile0/vram0/*`, and the NVIDIA
/// proprietary driver is read over NVML on a persistent worker isolate.
/// [includeUsage] and [includeMemory] keep a GPU-only or VRAM-only bar from
/// doing the other read; NVML is only consulted when the proprietary driver
/// or a discovered NVIDIA card is present, so AMD-only systems never load it.
class GpuSampler {
  GpuSampler({
    this.interval = const Duration(seconds: 1),
    this.includeUsage = true,
    this.includeMemory = true,
    String drmRoot = '/sys/class/drm',
    NvmlReader? nvml,
    String nvidiaDriverPath = '/proc/driver/nvidia/version',
    void Function(String message)? log,
  }) : _drmRoot = drmRoot,
       _nvml = nvml ?? NvmlReader(),
       _nvidiaDriverPath = nvidiaDriverPath,
       _log = log ?? _stderrLog;

  final Duration interval;

  /// Whether utilization is read. A VRAM-only bar sets this false.
  final bool includeUsage;

  /// Whether dedicated VRAM is read. A GPU-only bar sets this false.
  final bool includeMemory;
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
  var _resample = false;
  var _running = false;
  var _paused = false;
  var _generation = 0;
  var _disposed = false;
  final _controller = StreamController<List<GpuLoad>>.broadcast();

  Stream<List<GpuLoad>> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  bool get _hasNvidia =>
      (_nvidiaDriverPresent ??= File(_nvidiaDriverPath).existsSync()) ||
      _discoveredNvidia;

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
      _begin();
    }
  }

  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;
    _generation += 1;
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
    _begin();
  }

  void _begin() {
    unawaited(_tick());
    _timer ??= Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _paused = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    await _nvml.dispose();
    await _controller.close();
  }

  Future<void> _tick() async {
    if (_sampling) {
      _resample = true;
      return;
    }
    _sampling = true;
    final generation = _generation;
    try {
      final loads = await sample();
      // Drop work that belongs to the paused generation, including a tick
      // that started before pause and completed after a quick resume.
      if (generation != _generation || _paused || _controller.isClosed) {
        return;
      }
      _controller.add(loads);
    } finally {
      _sampling = false;
      if (_resample) {
        _resample = false;
        if (!_paused && !_controller.isClosed) {
          unawaited(_tick());
        }
      }
    }
  }

  /// One pass over the discovered cards, appending each reading to the
  /// card's series. Exposed so tests (and any caller wanting the series
  /// without the periodic timer) can drive it directly.
  Future<List<GpuLoad>> sample() async {
    _devices ??= _discover();
    final reads =
        <
          ({
            String id,
            String label,
            String? name,
            double? usage,
            int? memoryUsed,
            int? memoryTotal,
          })
        >[];
    for (final device in _devices!) {
      final usage = includeUsage && device.busyFile != null
          ? _busyPercent(device.busyFile!)
          : null;
      final memoryFiles = device.memoryFiles;
      final memory = includeMemory && memoryFiles != null
          ? _readMemory(memoryFiles)
          : null;
      if (usage == null && memory == null) {
        continue;
      }
      reads.add((
        id: device.id,
        label: device.label,
        name: null,
        usage: usage,
        memoryUsed: memory?.used,
        memoryTotal: memory?.total,
      ));
    }
    if (_hasNvidia) {
      if (await _canReadNvidiaWithoutWake()) {
        final read = await _nvml.read(
          includeUsage: includeUsage,
          includeMemory: includeMemory,
        );
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
            memoryUsed: nvidia.usedBytes,
            memoryTotal: nvidia.totalBytes,
          ));
        }
      } else if (includeUsage) {
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
            memoryUsed: null,
            memoryTotal: null,
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
            .append(
              read.usage,
              memoryUsedBytes: read.memoryUsed,
              memoryTotalBytes: read.memoryTotal,
            ),
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
        final memoryFiles = includeMemory ? _memoryFilesFor(device) : null;
        final hasBusy = includeUsage && busyFile.existsSync();
        final hasMemory =
            includeMemory &&
            memoryFiles != null &&
            (_readInt(memoryFiles.totalFile) ?? 0) > 0;
        if (!hasBusy && !hasMemory) {
          continue;
        }
        devices.add(
          _GpuDevice(
            id: name,
            label: _vendorLabel(vendor),
            busyFile: hasBusy ? busyFile : null,
            memoryFiles: hasMemory ? memoryFiles : null,
          ),
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

  ({int used, int total})? _readMemory(_GpuMemoryFiles files) {
    final total = _readInt(files.totalFile);
    final used = _readInt(files.usedFile);
    if (total == null || total <= 0 || used == null || used < 0) {
      return null;
    }
    return (used: used, total: total);
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
            memoryUsedBytes: load.memoryUsedBytes,
            memoryTotalBytes: load.memoryTotalBytes,
            memoryHistory: load.memoryHistory,
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
    required this.memoryFiles,
  });

  final String id;
  final String label;
  final File? busyFile;
  final _GpuMemoryFiles? memoryFiles;
}

class _GpuMemoryFiles {
  const _GpuMemoryFiles({required this.usedFile, required this.totalFile});

  final File usedFile;
  final File totalFile;
}

/// Finds the first supported dedicated-VRAM sysfs pair for one DRM device.
///
/// amdgpu and some i915/Arc cards publish `mem_info_vram_*`; Xe publishes
/// `tile0/vram0/{total,used}_bytes`. Both files must exist; the caller still
/// treats a zero or unreadable total as no memory.
_GpuMemoryFiles? _memoryFilesFor(String device) {
  final directTotal = File('$device/mem_info_vram_total');
  final directUsed = File('$device/mem_info_vram_used');
  if (directTotal.existsSync() && directUsed.existsSync()) {
    return _GpuMemoryFiles(usedFile: directUsed, totalFile: directTotal);
  }
  final xeTotal = File('$device/tile0/vram0/total_bytes');
  final xeUsed = File('$device/tile0/vram0/used_bytes');
  if (xeTotal.existsSync() && xeUsed.existsSync()) {
    return _GpuMemoryFiles(usedFile: xeUsed, totalFile: xeTotal);
  }
  return null;
}

int? _readInt(File file) {
  try {
    return int.tryParse(file.readAsStringSync().trim());
  } on FileSystemException {
    return null;
  }
}

/// Whether this machine publishes any dedicated GPU memory source.
///
/// Used by the settings availability probe. It intentionally treats a
/// present NVIDIA driver or card as available even when NVML is broken, so a
/// probe can never block a machine whose runtime query might work.
bool hasGpuMemorySource({
  String drmRoot = '/sys/class/drm',
  String nvidiaDriverPath = '/proc/driver/nvidia/version',
}) {
  if (File(nvidiaDriverPath).existsSync()) {
    return true;
  }
  final root = Directory(drmRoot);
  if (!root.existsSync()) {
    return false;
  }
  try {
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      if (!RegExp(r'^card\d+$').hasMatch(name)) {
        continue;
      }
      final device = '${entity.path}/device';
      if (File('$device/vendor').existsSync() &&
          File('$device/vendor').readAsStringSync().trim() == '0x10de') {
        return true;
      }
      final files = _memoryFilesFor(device);
      if (files != null && (_readInt(files.totalFile) ?? 0) > 0) {
        return true;
      }
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

void _stderrLog(String message) => stderr.writeln(message);
