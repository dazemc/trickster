import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'package:trickster/src/services/background_worker.dart';

/// One NVML pass: the samples, and the failure reason when the stack is
/// unavailable (a missing library, a driver/library mismatch, a dead
/// worker).
typedef NvmlRead = ({List<NvidiaGpuSample> samples, String? error});

/// One NVIDIA GPU utilization reading as a 0-1 fraction.
class NvidiaGpuSample {
  const NvidiaGpuSample({required this.index, required this.usage, this.name});

  /// NVML device index, stable across reads.
  final int index;

  final double usage;

  /// NVML device name, or null when the query is unavailable.
  final String? name;
}

/// Typed UI-isolate facade for NVML readings owned by the persistent NVIDIA
/// worker isolate.
///
/// The direct FFI calls execute only on its worker — never on the UI isolate,
/// where a blocking `nvmlInit`/query would stall the frame loop. A missing
/// library or worker failure remains a best-effort empty reading, with the
/// reason carried back so the caller can log it once.
class NvmlReader {
  NvmlReader({BackgroundWorker? worker})
    : _worker =
          worker ??
          BackgroundWorker(
            entrypoint: _nvidiaWorkerMain,
            debugName: 'trickster-nvml-worker',
          );

  final BackgroundWorker _worker;

  Future<NvmlRead> read() async {
    try {
      return await _worker.invoke<NvmlRead>(
        operation: _readNvidiaGpuSamples,
        decode: _decodeNvmlRead,
      );
    } on Object catch (error) {
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
            row.length == 3 &&
            row[0] is int &&
            row[1] is double &&
            (row[2] == null || row[2] is String))
          NvidiaGpuSample(
            index: row[0]! as int,
            usage: row[1]! as double,
            name: row[2] as String?,
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
  serveBackgroundWorker(bootstrap, (operation, _) {
    if (operation != _readNvidiaGpuSamples) {
      throw UnsupportedError('Unknown NVIDIA worker operation $operation');
    }
    return reader.read();
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

  static const _deviceNameCapacity = 96;

  List<Object?> read() {
    if (_unavailable || (_library == null && !_initialize())) {
      return <Object?>[_failure ?? 'NVML unavailable', const <Object?>[]];
    }
    final utilization = pkg_ffi.calloc<_NvmlUtilization>();
    final name = pkg_ffi.calloc<ffi.Uint8>(_deviceNameCapacity);
    try {
      final samples = <Object?>[];
      for (var index = 0; index < _devices.length; index += 1) {
        final device = _devices[index];
        if (_getUtilization(device, utilization) != 0) {
          continue;
        }
        samples.add(<Object?>[
          index,
          (utilization.ref.gpu / 100.0).clamp(0.0, 1.0),
          _readName(device, name),
        ]);
      }
      return <Object?>[null, samples];
    } finally {
      pkg_ffi.calloc.free(utilization);
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

  @ffi.Uint32()
  external int memory;
}
