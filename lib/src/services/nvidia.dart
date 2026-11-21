import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'package:trickster/src/services/background_worker.dart';

/// One NVML pass: the samples, and the failure reason when the stack is
/// unavailable (a missing library, a driver/library mismatch, a dead
/// worker).
typedef NvmlRead = ({List<NvidiaGpuSample> samples, String? error});

/// One NVIDIA GPU reading. Utilization and memory are independently optional:
/// a memory-only query leaves [usage] null, and a GPU-only query leaves the
/// byte fields null.
class NvidiaGpuSample {
  const NvidiaGpuSample({
    required this.index,
    this.usage,
    this.name,
    this.usedBytes,
    this.totalBytes,
  });

  /// NVML device index, stable across reads.
  final int index;

  /// GPU utilization as a 0-1 fraction, or null when it was not requested or
  /// could not be read.
  final double? usage;

  /// NVML device name, or null when the query is unavailable.
  final String? name;

  /// VRAM bytes in use and available, or null when memory was not requested,
  /// the device publishes no total, or the query failed.
  final int? usedBytes;
  final int? totalBytes;
}

/// Typed UI-isolate facade for NVML readings owned by the persistent NVIDIA
/// worker isolate.
///
/// The direct FFI calls execute only on its worker — never on the UI isolate,
/// where a blocking `nvmlInit`/query would stall the frame loop. A missing
/// library or worker failure remains a best-effort empty reading, with the
/// reason carried back so the caller can log it once.
class NvmlReader {
  NvmlReader({
    BackgroundWorker? worker,
    Duration requestTimeout = const Duration(seconds: 2),
    Duration cooldown = const Duration(seconds: 60),
  }) : _requestTimeout = requestTimeout,
       _cooldown = cooldown,
       _worker =
           worker ??
           BackgroundWorker(
             entrypoint: _nvidiaWorkerMain,
             debugName: 'trickster-nvml-worker',
             requestTimeout: requestTimeout,
           );

  final BackgroundWorker _worker;
  final Duration _requestTimeout;
  final Duration _cooldown;
  DateTime? _cooldownUntil;

  Future<NvmlRead> read({
    bool includeUsage = true,
    bool includeMemory = true,
  }) async {
    final now = DateTime.now();
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && now.isBefore(cooldownUntil)) {
      return (
        samples: const <NvidiaGpuSample>[],
        error: 'NVML request is cooling down after a timeout',
      );
    }
    try {
      final read = await _worker.invoke<NvmlRead>(
        operation: _readNvidiaGpuSamples,
        payload: <Object?>[includeUsage, includeMemory],
        decode: _decodeNvmlRead,
        timeout: _requestTimeout,
      );
      _cooldownUntil = null;
      return read;
    } on TimeoutException {
      _cooldownUntil = DateTime.now().add(_cooldown);
      return (
        samples: const <NvidiaGpuSample>[],
        error: 'NVML request timed out',
      );
    } on Object catch (error) {
      // An ordinary worker error (missing library, operation failure) does
      // not restart the worker or start a cooldown.
      return (samples: const <NvidiaGpuSample>[], error: '$error');
    }
  }

  Future<void> dispose() => _worker.close();
}

const int _readNvidiaGpuSamples = 1;

NvmlRead _decodeNvmlRead(Object? response) {
  if (response is! List<Object?> || response.length != 2) {
    throw const FormatException('Invalid NVIDIA worker response');
  }
  final error = response[0];
  final rows = response[1];
  if ((error != null && error is! String) || rows is! List<Object?>) {
    throw const FormatException('Invalid NVIDIA worker response');
  }
  return (
    samples: <NvidiaGpuSample>[
      for (final row in rows)
        if (row is List<Object?> &&
            row.length == 5 &&
            row[0] is int &&
            (row[1] == null || row[1] is double) &&
            (row[2] == null || row[2] is String) &&
            (row[3] == null || row[3] is int) &&
            (row[4] == null || row[4] is int))
          NvidiaGpuSample(
            index: row[0]! as int,
            usage: row[1] as double?,
            name: row[2] as String?,
            usedBytes: row[3] as int?,
            totalBytes: row[4] as int?,
          )
        else
          throw const FormatException('Invalid NVIDIA GPU sample'),
    ],
    error: error as String?,
  );
}

@pragma('vm:entry-point')
void _nvidiaWorkerMain(List<SendPort> bootstrap) {
  final reader = _NativeNvmlReader();
  serveBackgroundWorker(bootstrap, (operation, payload) {
    if (operation != _readNvidiaGpuSamples) {
      throw UnsupportedError('Unknown NVIDIA worker operation $operation');
    }
    var includeUsage = true;
    var includeMemory = true;
    if (payload is List<Object?> && payload.length == 2) {
      includeUsage = payload[0] != false;
      includeMemory = payload[1] != false;
    }
    return reader.read(
      includeUsage: includeUsage,
      includeMemory: includeMemory,
    );
  });
}

/// NVML is deliberately confined to the NVIDIA worker isolate. No native
/// handles or FFI-backed objects cross the isolate boundary.
final class _NativeNvmlReader {
  bool _unavailable = false;
  String? _failure;
  ffi.DynamicLibrary? _library;
  List<ffi.Pointer<ffi.Void>> _devices = const <ffi.Pointer<ffi.Void>>[];
  late final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_NvmlUtilization>)
  _getUtilization;
  int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int)?
  _getDeviceName;
  int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_NvmlMemory>)? _getMemory;

  static const _deviceNameCapacity = 96;

  List<Object?> read({
    required bool includeUsage,
    required bool includeMemory,
  }) {
    if (_unavailable || (_library == null && !_initialize())) {
      return <Object?>[_failure ?? 'NVML unavailable', const <Object?>[]];
    }
    final utilization = pkg_ffi.calloc<_NvmlUtilization>();
    final memory = pkg_ffi.calloc<_NvmlMemory>();
    final name = pkg_ffi.calloc<ffi.Uint8>(_deviceNameCapacity);
    try {
      final samples = <Object?>[];
      for (var index = 0; index < _devices.length; index += 1) {
        final device = _devices[index];
        double? usage;
        if (includeUsage && _getUtilization(device, utilization) == 0) {
          usage = (utilization.ref.gpu / 100.0).clamp(0.0, 1.0);
        }
        int? usedBytes;
        int? totalBytes;
        final getMemory = _getMemory;
        if (includeMemory &&
            getMemory != null &&
            getMemory(device, memory) == 0 &&
            memory.ref.total > 0) {
          usedBytes = memory.ref.used;
          totalBytes = memory.ref.total;
        }
        if (usage == null && totalBytes == null) {
          continue;
        }
        samples.add(<Object?>[
          index,
          usage,
          _readName(device, name),
          usedBytes,
          totalBytes,
        ]);
      }
      return <Object?>[null, samples];
    } finally {
      pkg_ffi.calloc.free(utilization);
      pkg_ffi.calloc.free(memory);
      pkg_ffi.calloc.free(name);
    }
  }

  String? _readName(
    ffi.Pointer<ffi.Void> device,
    ffi.Pointer<ffi.Uint8> buffer,
  ) {
    final getDeviceName = _getDeviceName;
    if (getDeviceName == null ||
        getDeviceName(device, buffer, _deviceNameCapacity) != 0) {
      return null;
    }
    return buffer.cast<pkg_ffi.Utf8>().toDartString();
  }

  bool _initialize() {
    try {
      final library = ffi.DynamicLibrary.open('libnvidia-ml.so.1');
      final init = library.lookupFunction<ffi.Int32 Function(), int Function()>(
        'nvmlInit_v2',
      );
      final initCode = init();
      if (initCode != 0) {
        // NVML error 18 is NVML_ERROR_LIB_RM_VERSION_MISMATCH: the userspace
        // library and the loaded kernel module disagree (a driver update
        // without a module reload).
        _failure = initCode == 18
            ? 'NVML driver/library version mismatch'
            : 'nvmlInit failed (code $initCode)';
        _unavailable = true;
        return false;
      }
      final getCount = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Uint32>),
            int Function(ffi.Pointer<ffi.Uint32>)
          >('nvmlDeviceGetCount_v2');
      final getHandle = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Pointer<ffi.Void>>),
            int Function(int, ffi.Pointer<ffi.Pointer<ffi.Void>>)
          >('nvmlDeviceGetHandleByIndex_v2');
      _getUtilization = library
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<_NvmlUtilization>,
            ),
            int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_NvmlUtilization>)
          >('nvmlDeviceGetUtilizationRates');
      try {
        _getDeviceName = library
            .lookupFunction<
              ffi.Int32 Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<ffi.Uint8>,
                ffi.Uint32,
              ),
              int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int)
            >('nvmlDeviceGetName');
      } on Object {
        _getDeviceName = null;
      }
      try {
        _getMemory = library
            .lookupFunction<
              ffi.Int32 Function(
                ffi.Pointer<ffi.Void>,
                ffi.Pointer<_NvmlMemory>,
              ),
              int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_NvmlMemory>)
            >('nvmlDeviceGetMemoryInfo');
      } on Object {
        _getMemory = null;
      }

      final count = pkg_ffi.calloc<ffi.Uint32>();
      final handle = pkg_ffi.calloc<ffi.Pointer<ffi.Void>>();
      try {
        if (getCount(count) != 0) {
          _unavailable = true;
          return false;
        }
        _devices = <ffi.Pointer<ffi.Void>>[
          for (var index = 0; index < count.value; index += 1)
            if (getHandle(index, handle) == 0) handle.value,
        ];
      } finally {
        pkg_ffi.calloc.free(count);
        pkg_ffi.calloc.free(handle);
      }
      _library = library;
      return true;
    } on Object catch (error) {
      _failure ??= 'NVML unavailable: $error';
      _unavailable = true;
      return false;
    }
  }
}

final class _NvmlUtilization extends ffi.Struct {
  @ffi.Uint32()
  external int gpu;

  /// Memory-controller utilization, not VRAM bytes. Never use this for the
  /// VRAM meter; `nvmlDeviceGetMemoryInfo` supplies used/total bytes.
  @ffi.Uint32()
  external int memory;
}

final class _NvmlMemory extends ffi.Struct {
  @ffi.Uint64()
  external int total;

  @ffi.Uint64()
  external int free;

  @ffi.Uint64()
  external int used;
}
