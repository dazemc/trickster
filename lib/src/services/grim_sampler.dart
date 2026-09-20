import 'dart:io';
import 'dart:ui' show Color, Rect;

import 'package:flutter/foundation.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

/// Captures one output's strip band with `grim` and extracts accent
/// candidates: the fallback when an output has no awww/swww image (a solid
/// or compositor-painted background). A missing grim binary degrades to no
/// candidates, silently.
class GrimSampler {
  GrimSampler({
    Future<Uint8List?> Function(List<String> args)? run,
    Future<List<Color>> Function(Uint8List encoded)? extract,
    bool? available,
  }) : _run = run ?? _runGrim,
       _extract = extract ?? extractWallpaperAccents,
       _available = available;

  final Future<Uint8List?> Function(List<String> args) _run;
  final Future<List<Color>> Function(Uint8List encoded) _extract;
  bool? _available;

  /// Whether the grim binary exists; probed once per process.
  Future<bool> available() async {
    final cached = _available;
    if (cached != null) {
      return cached;
    }
    try {
      // An argument-less run prints usage and exits non-zero; what matters
      // is that the binary started.
      await Process.run('grim', const <String>[]);
      _available = true;
    } on Object {
      _available = false;
    }
    return _available!;
  }

  /// The accent candidates of [output]'s strip band, or none when grim is
  /// missing, the band is empty, or the capture fails.
  Future<List<Color>> sample({
    required LayerOutput output,
    required SystemBarSide side,
    required double thickness,
  }) async {
    final region = stripBand(output, side, thickness);
    if (region == null || !await available()) {
      return const <Color>[];
    }
    Uint8List? bytes;
    try {
      bytes = await _run([
        '-o',
        output.name,
        '-g',
        '${region.left.round()},${region.top.round()} '
            '${region.width.round()}x${region.height.round()}',
        '-t',
        'png',
        '-',
      ]);
    } on Object {
      return const <Color>[];
    }
    if (bytes == null || bytes.isEmpty) {
      return const <Color>[];
    }
    try {
      return await _extract(bytes);
    } on Object {
      return const <Color>[];
    }
  }
}

/// The band next to the strip on [side], in output-local logical pixels: the
/// desktop the bar sits on. The strip itself is never captured, or our own
/// pills would feed the sampler. Null when the band would be empty.
@visibleForTesting
Rect? stripBand(LayerOutput output, SystemBarSide side, double thickness) {
  final width = output.width.toDouble();
  final height = output.height.toDouble();
  final band = thickness.clamp(1.0, 400.0);
  final region = switch (side) {
    SystemBarSide.top => Rect.fromLTWH(0, band, width, band),
    SystemBarSide.bottom => Rect.fromLTWH(0, height - 2 * band, width, band),
    SystemBarSide.left => Rect.fromLTWH(band, 0, band, height),
    SystemBarSide.right => Rect.fromLTWH(width - 2 * band, 0, band, height),
    SystemBarSide.hidden => null,
  };
  if (region == null) {
    return null;
  }
  final clipped = region.intersect(Rect.fromLTWH(0, 0, width, height));
  if (clipped.width < 1 || clipped.height < 1) {
    return null;
  }
  return clipped;
}

Future<Uint8List?> _runGrim(List<String> args) async {
  final result = await Process.run('grim', args);
  if (result.exitCode != 0) {
    return null;
  }
  final stdout = result.stdout;
  if (stdout is! List<int>) {
    return null;
  }
  return Uint8List.fromList(stdout);
}
