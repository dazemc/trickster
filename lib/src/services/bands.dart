import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:trickster/src/services/pipewire.dart';

/// Bars the analyzer emits.
const int bandCount = 12;

/// The analyzer's window; a power of two for the radix-2 FFT.
const int _fftSize = 1024;

/// Levels map this dB range onto 0..1; quieter batches rest at zero.
const double _floorDb = -60;

/// Normalized band levels for one interleaved F32 batch.
///
/// Downmixes to mono, gates on RMS (silence rests), windows with a Hann
/// taper, runs a 1024-point FFT, and folds the spectrum into [bands]
/// log-spaced groups from 40 Hz to Nyquist, each mapped from dB onto 0..1.
/// Pure and top-level so unit tests can pin the mapping and the worker
/// isolate can call it directly.
List<double> analyzeBands(
  Float32List samples, {
  required int rate,
  required int channels,
  int bands = bandCount,
}) {
  if (channels <= 0 || samples.length < channels || rate <= 0) {
    return List<double>.filled(bands, 0);
  }
  final frames = samples.length ~/ channels;
  final count = math.min(frames, _fftSize);
  final mono = Float64List(_fftSize);
  var energy = 0.0;
  for (var frame = 0; frame < count; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      sum += samples[frame * channels + channel];
    }
    final value = sum / channels;
    energy += value * value;
    mono[frame] = value;
  }
  final rms = math.sqrt(energy / count);
  if (rms < 1e-4) {
    return List<double>.filled(bands, 0);
  }
  if (count > 1) {
    for (var frame = 0; frame < count; frame++) {
      mono[frame] *= 0.5 * (1 - math.cos(2 * math.pi * frame / (count - 1)));
    }
  }
  final real = Float64List.fromList(mono);
  final imaginary = Float64List(_fftSize);
  _fft(real, imaginary);

  final bins = _fftSize ~/ 2;
  final magnitude = Float64List(bins);
  for (var bin = 0; bin < bins; bin++) {
    magnitude[bin] =
        math.sqrt(real[bin] * real[bin] + imaginary[bin] * imaginary[bin]) /
        count;
  }

  final nyquist = math.min(16000.0, rate / 2);
  final edges = <int>[
    for (var band = 0; band <= bands; band++)
      (40 * math.pow(nyquist / 40, band / bands) * _fftSize / rate)
          .round()
          .clamp(0, bins - 1),
  ];
  final levels = List<double>.filled(bands, 0);
  for (var band = 0; band < bands; band++) {
    final start = edges[band];
    final end = math.max(start + 1, edges[band + 1]);
    var peak = 0.0;
    for (var bin = start; bin < end; bin++) {
      peak = math.max(peak, magnitude[bin]);
    }
    final db = 20 * (math.log(peak + 1e-9) / math.ln10);
    levels[band] = ((db - _floorDb) / -_floorDb).clamp(0.0, 1.0);
  }
  return levels;
}

/// In-place iterative radix-2 Cooley-Tukey FFT.
void _fft(Float64List real, Float64List imaginary) {
  final n = real.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    while (j & bit != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      var swap = real[i];
      real[i] = real[j];
      real[j] = swap;
      swap = imaginary[i];
      imaginary[i] = imaginary[j];
      imaginary[j] = swap;
    }
  }
  for (var length = 2; length <= n; length <<= 1) {
    final angle = -2 * math.pi / length;
    final stepReal = math.cos(angle);
    final stepImaginary = math.sin(angle);
    final half = length >> 1;
    for (var start = 0; start < n; start += length) {
      var curReal = 1.0;
      var curImaginary = 0.0;
      for (var k = 0; k < half; k++) {
        final evenReal = real[start + k];
        final evenImaginary = imaginary[start + k];
        final oddReal =
            real[start + k + half] * curReal -
            imaginary[start + k + half] * curImaginary;
        final oddImaginary =
            real[start + k + half] * curImaginary +
            imaginary[start + k + half] * curReal;
        real[start + k] = evenReal + oddReal;
        imaginary[start + k] = evenImaginary + oddImaginary;
        real[start + k + half] = evenReal - oddReal;
        imaginary[start + k + half] = evenImaginary - oddImaginary;
        final nextReal = curReal * stepReal - curImaginary * stepImaginary;
        curImaginary = curReal * stepImaginary + curImaginary * stepReal;
        curReal = nextReal;
      }
    }
  }
}

/// Turns PCM frames into band levels on a worker isolate.
///
/// One isolate per [start]; [stop] kills it, so nothing lingers while no
/// media plays. The capture is owned here too: no stream, no isolate, no
/// subscription survives a stop.
class BandAnalyzer {
  BandAnalyzer({PipeWireCapture? capture, this.bands = bandCount})
    : _capture = capture ?? PipeWireCapture();

  final PipeWireCapture _capture;
  final int bands;
  final StreamController<List<double>> _levels =
      StreamController<List<double>>.broadcast();

  StreamSubscription<PipeWireFrame>? _frames;
  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _ready;
  ReceivePort? _results;
  ReceivePort? _errors;
  ReceivePort? _exits;
  var _generation = 0;

  Stream<List<double>> get levels => _levels.stream;

  bool get isRunning => _isolate != null;

  /// Opens the monitor and spawns the worker; false when the capture has no
  /// default sink or the worker fails to start.
  Future<bool> start() async {
    if (_isolate != null) {
      return true;
    }
    if (!await _capture.start()) {
      return false;
    }
    final generation = ++_generation;
    final ready = ReceivePort();
    final results = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    try {
      final isolate = await Isolate.spawn<List<Object?>>(
        _bandsMain,
        <Object?>[ready.sendPort, results.sendPort, bands],
        debugName: 'trickster-bands',
        errorsAreFatal: true,
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      final port = await ready.first.timeout(const Duration(seconds: 5));
      if (port is! SendPort || generation != _generation) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('band worker startup was superseded');
      }
      _isolate = isolate;
      _worker = port;
      _ready = ready;
      _results = results;
      _errors = errors;
      _exits = exits;
      results.listen((message) {
        if (message is List && message.length == bands) {
          _levels.add(<double>[
            for (final level in message)
              if (level is double) level else 0,
          ]);
        }
      });
      errors.listen((_) {});
      exits.listen((_) {
        if (generation == _generation) {
          _teardown();
          // The bars rest when the worker dies.
          _levels.add(List<double>.filled(bands, 0));
        }
      });
      _listenFrames();
      return true;
    } on Object {
      if (generation == _generation) {
        _generation += 1;
      }
      _teardown();
      await _capture.stop();
      return false;
    }
  }

  Future<void> stop() async {
    _generation += 1;
    final frames = _frames;
    _frames = null;
    unawaited(frames?.cancel());
    _teardown();
    await _capture.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _levels.close();
    _capture.dispose();
  }

  void _feed(PipeWireFrame frame) {
    _worker?.send(<Object?>[frame.samples, frame.rate, frame.channels]);
  }

  /// Listens for PCM batches, replacing any previous listener (none while a
  /// start is in flight; stop clears the field first).
  void _listenFrames() {
    unawaited(_frames?.cancel());
    _frames = _capture.frames.listen(_feed);
  }

  void _teardown() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _worker = null;
    _ready?.close();
    _ready = null;
    _results?.close();
    _results = null;
    _errors?.close();
    _errors = null;
    _exits?.close();
    _exits = null;
  }
}

@pragma('vm:entry-point')
void _bandsMain(List<Object?> bootstrap) {
  final ready = bootstrap[0] as SendPort;
  final results = bootstrap[1] as SendPort;
  final bands = bootstrap[2] as int;
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((message) {
    if (message is! List || message.length != 3) {
      return;
    }
    final samples = message[0];
    final rate = message[1];
    final channels = message[2];
    if (samples is! Float32List || rate is! int || channels is! int) {
      return;
    }
    results.send(
      analyzeBands(samples, rate: rate, channels: channels, bands: bands),
    );
  });
}
