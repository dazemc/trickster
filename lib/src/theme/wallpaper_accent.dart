import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ported from Denial's `wallpaper_accent.dart` (GPL-3.0-or-later).
///
/// Decodes [encoded] at thumbnail size and returns its dominant vibrant
/// seed, or null for effectively monochrome images.
Future<Color?> extractWallpaperAccent(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(
    encoded,
    targetWidth: 64,
    allowUpscaling: false,
  );
  final ui.Image image;
  try {
    image = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return null;
    }
    return dominantVibrantColor(data);
  } finally {
    image.dispose();
  }
}

/// Scores 15-degree hue buckets by chroma-weighted frequency over raw RGBA
/// pixels and rebuilds the winning bucket as a canonical seed. Near-gray and
/// near-black pixels carry no vote; when nothing votes the image has no
/// usable accent.
@visibleForTesting
Color? dominantVibrantColor(ByteData rgba) {
  const bucketCount = 24;
  const bucketDegrees = 360.0 / bucketCount;
  final weights = Float64List(bucketCount);
  final hueSin = Float64List(bucketCount);
  final hueCos = Float64List(bucketCount);
  final saturations = Float64List(bucketCount);

  final pixelCount = rgba.lengthInBytes ~/ 4;
  for (var index = 0; index < pixelCount; index += 1) {
    final offset = index * 4;
    final r = rgba.getUint8(offset) / 255.0;
    final g = rgba.getUint8(offset + 1) / 255.0;
    final b = rgba.getUint8(offset + 2) / 255.0;
    final high = math.max(r, math.max(g, b));
    final low = math.min(r, math.min(g, b));
    final chroma = high - low;
    final saturation = high == 0.0 ? 0.0 : chroma / high;
    if (saturation < 0.15 || high < 0.12) {
      continue;
    }

    var hue = 0.0;
    if (chroma > 0.0) {
      if (high == r) {
        hue = 60.0 * (((g - b) / chroma) % 6.0);
      } else if (high == g) {
        hue = 60.0 * (((b - r) / chroma) + 2.0);
      } else {
        hue = 60.0 * (((r - g) / chroma) + 4.0);
      }
    }
    if (hue < 0.0) {
      hue += 360.0;
    }

    final weight = saturation * saturation * high;
    final bucket = (hue / bucketDegrees).floor() % bucketCount;
    final radians = hue * math.pi / 180.0;
    weights[bucket] += weight;
    hueSin[bucket] += math.sin(radians) * weight;
    hueCos[bucket] += math.cos(radians) * weight;
    saturations[bucket] += saturation * weight;
  }

  var best = 0;
  for (var bucket = 1; bucket < bucketCount; bucket += 1) {
    if (weights[bucket] > weights[best]) {
      best = bucket;
    }
  }
  // A vibrant accent needs a real constituency; a handful of stray colored
  // pixels in a gray image must not theme the whole shell.
  if (pixelCount == 0 || weights[best] < pixelCount * 0.002) {
    return null;
  }

  var hue = math.atan2(hueSin[best], hueCos[best]) * 180.0 / math.pi;
  if (hue < 0.0) {
    hue += 360.0;
  }
  final saturation = (saturations[best] / weights[best])
      .clamp(0.35, 0.74)
      .toDouble();
  return HSVColor.fromAHSV(1.0, hue, saturation, 0.65).toColor();
}
