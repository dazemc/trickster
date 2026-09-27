import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/bands.dart';

/// Interleaved stereo tone.
Float32List _sine({
  required double hz,
  double amplitude = 0.5,
  int rate = 48000,
  int frames = 1024,
  int channels = 2,
}) {
  final samples = Float32List(frames * channels);
  for (var frame = 0; frame < frames; frame++) {
    final value = amplitude * math.sin(2 * math.pi * hz * frame / rate);
    for (var channel = 0; channel < channels; channel++) {
      samples[frame * channels + channel] = value;
    }
  }
  return samples;
}

void main() {
  test('a 1 kHz tone lands in the band that contains it', () {
    final levels = analyzeBands(_sine(hz: 1000), rate: 48000, channels: 2);

    expect(levels, hasLength(bandCount));
    // Band edges run 40 Hz to 16 kHz log-spaced: 1 kHz falls in band 6.
    final loudest = levels.indexOf(levels.reduce(math.max));
    expect(loudest, 6);
    expect(levels[6], greaterThan(0.5));
    expect(levels[0], lessThan(levels[6]));
    expect(levels[bandCount - 1], lessThan(levels[6]));
  });

  test('silence rests at zero', () {
    final levels = analyzeBands(Float32List(2048), rate: 48000, channels: 2);

    expect(levels, everyElement(0));
  });

  test('levels stay normalized for loud input', () {
    final levels = analyzeBands(
      _sine(hz: 440, amplitude: 4),
      rate: 48000,
      channels: 2,
    );

    expect(levels, everyElement(inInclusiveRange(0, 1)));
    expect(levels.reduce(math.max), greaterThan(0.8));
  });

  test('degenerate input rests instead of throwing', () {
    expect(
      analyzeBands(Float32List(0), rate: 48000, channels: 2),
      everyElement(0),
    );
    expect(analyzeBands(Float32List(8), rate: 0, channels: 2), everyElement(0));
    expect(
      analyzeBands(Float32List(8), rate: 48000, channels: 0),
      everyElement(0),
    );
  });
}
