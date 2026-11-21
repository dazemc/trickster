import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:equatable/equatable.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:trickster/src/services/background_worker.dart';

/// One statvfs reading in bytes plus the configured mount path.
class DiskSample extends Equatable {
  const DiskSample({
    this.path = '/',
    this.usedBytes,
    this.totalBytes,
    this.freeBytes,
  });

  final String path;
  final int? usedBytes;
  final int? totalBytes;
  final int? freeBytes;

  double? get fraction {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) {
      return null;
    }
    return (used / total).clamp(0.0, 1.0);
  }

  static DiskSample fromUsage(String path, StatvfsUsage usage) {
    final total = usage.blocks * usage.fragmentSize;
    final used = (usage.blocks - usage.blocksFree) * usage.fragmentSize;
    final free = usage.blocksAvailable * usage.fragmentSize;
    if (total <= 0) {
      return DiskSample(path: path);
    }
    return DiskSample(
      path: path,
      usedBytes: used,
      totalBytes: total,
      freeBytes: free,
    );
  }

  @override
  List<Object?> get props => [path, usedBytes, totalBytes, freeBytes];

  Map<String, Object?> toJson() => {
    'path': path,
    'used_bytes': usedBytes,
    'total_bytes': totalBytes,
    'free_bytes': freeBytes,
    'fraction': fraction,
  };

  static DiskSample fromJson(Map<String, dynamic> json) => DiskSample(
    path: (json['path'] as String?) ?? '/',
    usedBytes: (json['used_bytes'] as num?)?.toInt(),
    totalBytes: (json['total_bytes'] as num?)?.toInt(),
    freeBytes: (json['free_bytes'] as num?)?.toInt(),
  );
}

/// Raw fields from `struct statvfs` needed to compute the disk fractions.
class StatvfsUsage extends Equatable {
  const StatvfsUsage({
    required this.fragmentSize,
    required this.blocks,
    required this.blocksFree,
    required this.blocksAvailable,
  });

  final int fragmentSize;
  final int blocks;
  final int blocksFree;
  final int blocksAvailable;

  @override
  List<Object?> get props => [
    fragmentSize,
    blocks,
    blocksFree,
    blocksAvailable,
  ];
}

/// Reads one statvfs usage, off the UI isolate in production.
abstract interface class DiskUsageReader {
  Future<StatvfsUsage?> read(String path);

  Future<void> dispose();
}

/// A bounded path buffer used by the statvfs worker.
const int _maxPathBytes = 4096;

/// Reads statvfs on a persistent worker isolate so the UI isolate never blocks
/// on the filesystem and the native buffers are reused across samples.
class SystemDiskUsageReader implements DiskUsageReader {
  SystemDiskUsageReader({
    BackgroundWorker? worker,
    Duration requestTimeout = const Duration(seconds: 5),
  }) : _requestTimeout = requestTimeout,
       _worker =
           worker ??
           BackgroundWorker(
             entrypoint: _diskWorkerMain,
             debugName: 'trickster-disk-worker',
             requestTimeout: requestTimeout,
           );

  final BackgroundWorker _worker;
  final Duration _requestTimeout;
  var _started = false;

  @override
  Future<StatvfsUsage?> read(String path) async {
    if (path.isEmpty || path.length >= _maxPathBytes) {
      return null;
    }
    _started = true;
    try {
      return await _worker.invoke<StatvfsUsage?>(
        operation: _readStatvfs,
        payload: path,
        decode: _decodeStatvfs,
        timeout: _requestTimeout,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_started) {
      try {
        await _worker.invoke<void>(
          operation: _disposeStatvfs,
          decode: (_) {},
          timeout: _requestTimeout,
        );
      } on Object {
        // The worker may already be gone; close is still safe.
      }
    }
    await _worker.close();
  }
}

const int _readStatvfs = 1;
const int _disposeStatvfs = 2;

StatvfsUsage? _decodeStatvfs(Object? response) {
  if (response == null) {
    return null;
  }
  if (response is! List<Object?> || response.length != 4) {
    throw const FormatException('Invalid statvfs worker response');
  }
  final values = <int>[];
  for (final value in response) {
    if (value is! int) {
      throw const FormatException('Invalid statvfs worker value');
    }
    values.add(value);
  }
  return StatvfsUsage(
    fragmentSize: values[3],
    blocks: values[0],
    blocksFree: values[1],
    blocksAvailable: values[2],
  );
}

@pragma('vm:entry-point')
void _diskWorkerMain(List<SendPort> bootstrap) {
  final reader = _NativeStatvfsReader();
  serveBackgroundWorker(bootstrap, (operation, payload) {
    if (operation == _readStatvfs && payload is String) {
      return reader.read(payload);
    }
    if (operation == _disposeStatvfs) {
      reader.dispose();
      return null;
    }
    throw UnsupportedError('Unknown disk worker operation $operation');
  });
}

/// statvfs is confined to the disk worker isolate. No native handles cross
/// the isolate boundary.
final class _NativeStatvfsReader {
  bool _initialized = false;
  ffi.DynamicLibrary? _library;
  int Function(ffi.Pointer<pkg_ffi.Utf8>, ffi.Pointer<_Statvfs>)? _statvfs;
  ffi.Pointer<_Statvfs>? _statvfsBuffer;
  ffi.Pointer<ffi.Uint8>? _pathBuffer;

  List<Object?>? read(String path) {
    if (!_initialize()) {
      return null;
    }
    final bytes = utf8.encode(path);
    if (bytes.isEmpty || bytes.length >= _maxPathBytes) {
      return null;
    }
    final pathBuffer = _pathBuffer!;
    final pathBytes = pathBuffer.asTypedList(_maxPathBytes);
    pathBytes.fillRange(0, _maxPathBytes, 0);
    pathBytes.setRange(0, bytes.length, bytes);
    final statvfsBuffer = _statvfsBuffer!;
    if (_statvfs!(pathBuffer.cast(), statvfsBuffer) != 0) {
      return null;
    }
    final fragmentSize = statvfsBuffer.ref.fFragmentSize == 0
        ? statvfsBuffer.ref.fBlockSize
        : statvfsBuffer.ref.fFragmentSize;
    return <Object?>[
      statvfsBuffer.ref.fBlocks,
      statvfsBuffer.ref.fBlocksFree,
      statvfsBuffer.ref.fBlocksAvailable,
      fragmentSize,
    ];
  }

  bool _initialize() {
    if (_initialized) {
      return _statvfs != null;
    }
    _initialized = true;
    try {
      _library = ffi.DynamicLibrary.process();
      _statvfs = _library!
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<pkg_ffi.Utf8>,
              ffi.Pointer<_Statvfs>,
            ),
            int Function(ffi.Pointer<pkg_ffi.Utf8>, ffi.Pointer<_Statvfs>)
          >('statvfs');
      _statvfsBuffer = pkg_ffi.calloc<_Statvfs>();
      _pathBuffer = pkg_ffi.calloc<ffi.Uint8>(_maxPathBytes);
      return true;
    } on Object {
      _statvfs = null;
      return false;
    }
  }

  void dispose() {
    final statvfsBuffer = _statvfsBuffer;
    if (statvfsBuffer != null) {
      pkg_ffi.calloc.free(statvfsBuffer);
      _statvfsBuffer = null;
    }
    final pathBuffer = _pathBuffer;
    if (pathBuffer != null) {
      pkg_ffi.calloc.free(pathBuffer);
      _pathBuffer = null;
    }
    _statvfs = null;
  }
}

/// Validates a disk mount path before it reaches the worker. The bar accepts
/// absolute paths only; the length bound matches the bounded native buffer.
void validateDiskPath(String path) {
  if (path.isEmpty ||
      !path.startsWith('/') ||
      path.length >= _maxPathBytes ||
      path.codeUnits.any((unit) => unit < 0x20)) {
    throw ArgumentError.value(path, 'path', 'must be an absolute mount path');
  }
}

/// Samples one configured mount every 30 seconds. A failed statvfs emits an
/// empty sample only when a reading was previously visible, so the pill hides
/// instead of showing a stale or synthetic value.
class DiskSampler {
  DiskSampler({
    this.interval = const Duration(seconds: 30),
    this.path = '/',
    DiskUsageReader? reader,
  }) : _reader = reader ?? SystemDiskUsageReader() {
    validateDiskPath(path);
    _latest = DiskSample(path: path);
  }

  final Duration interval;
  final String path;
  final DiskUsageReader _reader;
  late DiskSample _latest;
  Timer? _timer;
  var _sampling = false;
  var _resample = false;
  var _running = false;
  var _paused = false;
  var _generation = 0;
  var _disposed = false;
  final _controller = StreamController<DiskSample>.broadcast();

  Stream<DiskSample> get snapshots => _controller.stream;

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
      unawaited(_sample());
      _schedule();
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
    _generation += 1;
    if (!_running) {
      return;
    }
    unawaited(_sample());
    _schedule();
  }

  void _schedule() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(_sample()));
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
    await _reader.dispose();
    await _controller.close();
  }

  Future<void> _sample() async {
    if (_sampling) {
      _resample = true;
      return;
    }
    _sampling = true;
    final generation = _generation;
    try {
      StatvfsUsage? usage;
      try {
        usage = await _reader.read(path);
      } on Object {
        usage = null;
      }
      if (!_running ||
          _paused ||
          _disposed ||
          generation != _generation ||
          _controller.isClosed) {
        return;
      }
      if (usage == null) {
        if (_latest.usedBytes != null) {
          _latest = DiskSample(path: path);
          _controller.add(_latest);
        }
        return;
      }
      final next = DiskSample.fromUsage(path, usage);
      if (next.fraction == null) {
        if (_latest.usedBytes != null) {
          _latest = DiskSample(path: path);
          _controller.add(_latest);
        }
        return;
      }
      _latest = next;
      _controller.add(_latest);
    } finally {
      _sampling = false;
      if (_resample) {
        _resample = false;
        if (!_paused && !_disposed && _running) {
          unawaited(_sample());
        }
      }
    }
  }
}

final class _Statvfs extends ffi.Struct {
  @ffi.Uint64()
  external int fBlockSize;

  @ffi.Uint64()
  external int fFragmentSize;

  @ffi.Uint64()
  external int fBlocks;

  @ffi.Uint64()
  external int fBlocksFree;

  @ffi.Uint64()
  external int fBlocksAvailable;

  @ffi.Uint64()
  external int fFiles;

  @ffi.Uint64()
  external int fFilesFree;

  @ffi.Uint64()
  external int fFilesAvailable;

  @ffi.Uint64()
  external int fFilesystemId;

  @ffi.Uint64()
  external int fFlag;

  @ffi.Uint64()
  external int fNameMax;

  @ffi.Uint32()
  external int fType;

  @ffi.Array(5)
  external ffi.Array<ffi.Int32> fSpare;
}
