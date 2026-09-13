import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'background_worker.dart';

/// One NVIDIA GPU utilization reading as a 0-1 fraction.
class NvidiaGpuSample {
  const NvidiaGpuSample({required this.index, required this.usage});

  /// NVML device index, stable across reads.
  final int index;

  final double usage;
}

/// Typed UI-isolate facade for NVML readings owned by the persistent NVIDIA
/// worker isolate.
///
/// The direct FFI calls execute only on its worker — never on the UI isolate,
/// where a blocking `nvmlInit`/query would stall the frame loop. A missing
/// library or worker failure remains a best-effort empty reading.
class NvmlReader {
  NvmlReader({BackgroundWorker? worker})
    : _worker =
          worker ??
          BackgroundWorker(
            entrypoint: _nvidiaWorkerMain,
            debugName: 'trickster-nvml-worker',
          );

  final BackgroundWorker _worker;

  Future<List<NvidiaGpuSample>> read() async {
    try {
      return await _worker.invoke<List<NvidiaGpuSample>>(
        operation: _readNvidiaGpuSamples,
        decode: _decodeNvidiaGpuSamples,
      );
    } on Object {
      return const <NvidiaGpuSample>[];
    }
  }

  Future<void> dispose() => _worker.close();
}

const int _readNvidiaGpuSamples = 1;

List<NvidiaGpuSample> _decodeNvidiaGpuSamples(Object? response) {
  if (response is! List<Object?>) {
    throw const FormatException('Invalid NVIDIA worker response');
  }
  return <NvidiaGpuSample>[
    for (final row in response)
      if (row is List<Object?> &&
          row.length == 2 &&
          row[0] is int &&
          row[1] is double)
        NvidiaGpuSample(index: row[0]! as int, usage: row[1]! as double)
      else
        throw const FormatException('Invalid NVIDIA GPU sample'),
  ];
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
  ffi.DynamicLibrary? _library;
  List<ffi.Pointer<ffi.Void>> _devices = const <ffi.Pointer<ffi.Void>>[];
  late final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<_NvmlUtilization>)
  _getUtilization;

  List<Object?> read() {
    if (_unavailable || (_library == null && !_initialize())) {
      return const <Object?>[];
    }
    final utilization = pkg_ffi.calloc<_NvmlUtilization>();
    try {
      final samples = <Object?>[];
      for (var index = 0; index < _devices.length; index += 1) {
        if (_getUtilization(_devices[index], utilization) != 0) {
          continue;
        }
        samples.add(<Object?>[
          index,
          (utilization.ref.gpu / 100.0).clamp(0.0, 1.0),
        ]);
      }
      return samples;
    } finally {
      pkg_ffi.calloc.free(utilization);
    }
  }

  bool _initialize() {
    try {
      final library = ffi.DynamicLibrary.open('libnvidia-ml.so.1');
      final init = library.lookupFunction<ffi.Int32 Function(), int Function()>(
        'nvmlInit_v2',
      );
      if (init() != 0) {
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
    } on Object {
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
