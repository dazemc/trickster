import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/bands.dart';

import 'support/fake_pipewire.dart';

/// Interleaved stereo tone, shaped like the runner's frames.
Float32List _sine({required double hz, int frames = 1024, int channels = 2}) {
  final samples = Float32List(frames * channels);
  for (var frame = 0; frame < frames; frame++) {
    final value = 0.5 * math.sin(2 * math.pi * hz * frame / 48000);
    for (var channel = 0; channel < channels; channel++) {
      samples[frame * channels + channel] = value;
    }
  }
  return samples;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a running analyzer turns frames into levels', () async {
    final capture = FakePipeWireCapture();
    final analyzer = BandAnalyzer(capture: capture);
    addTearDown(analyzer.dispose);

    expect(await analyzer.start(), isTrue);
    expect(analyzer.isRunning, isTrue);

    final next = analyzer.levels.first;
    capture.emit(_sine(hz: 1000));
    final levels = await next.timeout(const Duration(seconds: 10));

    expect(levels, hasLength(bandCount));
    expect(levels[6], greaterThan(0.5));
  });

  test('stop kills the worker and closes the monitor', () async {
    final capture = FakePipeWireCapture();
    final analyzer = BandAnalyzer(capture: capture);
    addTearDown(analyzer.dispose);

    await analyzer.start();
    await analyzer.stop();

    expect(analyzer.isRunning, isFalse);
    expect(capture.stops, hasLength(1));
  });

  test('a refused capture leaves the analyzer stopped', () async {
    final capture = FakePipeWireCapture(startResult: false);
    final analyzer = BandAnalyzer(capture: capture);
    addTearDown(analyzer.dispose);

    expect(await analyzer.start(), isFalse);
    expect(analyzer.isRunning, isFalse);
    expect(capture.starts, hasLength(1));
  });
}
