import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Bounds for one wallpaper accent source. The byte cap runs before the file
/// is read; the dimension and pixel caps run before a codec is instantiated.
/// The decode cap keeps the pixel scan at thumbnail size.
class WallpaperSourceLimits {
  const WallpaperSourceLimits({
    this.maxBytes = 64 * 1024 * 1024,
    this.maxDimension = 16384,
    this.maxPixels = 40000000,
    this.maxDecodedDimension = 64,
  });

  /// Largest encoded source accepted, in bytes.
  final int maxBytes;

  /// Largest width or height accepted.
  final int maxDimension;

  /// Largest width * height accepted (40 MP covers 8K UHD at 33.2 MP).
  final int maxPixels;

  /// Longest side of the decoded thumbnail.
  final int maxDecodedDimension;

  bool allowsEncoded(int length) => length > 0 && length <= maxBytes;

  bool allowsSource(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= maxDimension &&
      height <= maxDimension &&
      width * height <= maxPixels;
}

/// Ported from Denial's `wallpaper_accent.dart` (GPL-3.0-or-later).
///
/// Decodes [encoded] at thumbnail size and returns its dominant vibrant
/// seed, or null for effectively monochrome images.
Future<Color?> extractWallpaperAccent(
  Uint8List encoded, {
  WallpaperSourceLimits limits = const WallpaperSourceLimits(),
}) async =>
    (await extractWallpaperAccents(encoded, limits: limits)).firstOrNull;

/// The wallpaper's potential accents, strongest first.
///
/// The source is rejected by byte size, intrinsic dimensions, and pixel count
/// before a codec is created. Only the first frame of an animated source is
/// decoded, and both target dimensions are bounded.
Future<List<Color>> extractWallpaperAccents(
  Uint8List encoded, {
  WallpaperSourceLimits limits = const WallpaperSourceLimits(),
}) async {
  if (!limits.allowsEncoded(encoded.lengthInBytes)) {
    return const <Color>[];
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (!limits.allowsSource(descriptor.width, descriptor.height)) {
      return const <Color>[];
    }
    final longest = math.max(descriptor.width, descriptor.height);
    final scale = math.min(1.0, limits.maxDecodedDimension / longest);
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return const <Color>[];
    }
    return vibrantCandidates(data);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Scores 15-degree hue buckets by chroma-weighted frequency over raw RGBA
/// pixels and rebuilds the winning bucket as a canonical seed. Near-gray and
/// near-black pixels carry no vote; when nothing votes the image has no
/// usable accent.
@visibleForTesting
Color? dominantVibrantColor(ByteData rgba) =>
    vibrantCandidates(rgba).firstOrNull;

/// The wallpaper's potential accents, strongest first: the top hue buckets
/// at least 24 degrees apart, each rebuilt as a canonical seed.
@visibleForTesting
List<Color> vibrantCandidates(ByteData rgba, {int max = 5}) {
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

  // A vibrant accent needs a real constituency; a handful of stray colored
  // pixels in a gray image must not theme the whole shell.
  if (pixelCount == 0) {
    return const <Color>[];
  }
  final threshold = pixelCount * 0.002;
  final order = List<int>.generate(bucketCount, (bucket) => bucket)
    ..sort((left, right) => weights[right].compareTo(weights[left]));

  Color seedFor(int bucket) {
    var hue = math.atan2(hueSin[bucket], hueCos[bucket]) * 180.0 / math.pi;
    if (hue < 0.0) {
      hue += 360.0;
    }
    final saturation = (saturations[bucket] / weights[bucket])
        .clamp(0.35, 0.74)
        .toDouble();
    return HSVColor.fromAHSV(1.0, hue, saturation, 0.65).toColor();
  }

  final buckets = <int>[];
  for (final bucket in order) {
    if (weights[bucket] < threshold) {
      break;
    }
    final hue = HSVColor.fromColor(seedFor(bucket)).hue;
    final duplicate = buckets.any((picked) {
      final other = HSVColor.fromColor(seedFor(picked)).hue;
      final distance = (hue - other).abs();
      return math.min(distance, 360.0 - distance) < 24.0;
    });
    if (duplicate) {
      continue;
    }
    buckets.add(bucket);
    if (buckets.length == max) {
      break;
    }
  }
  return [for (final bucket in buckets) seedFor(bucket)];
}

/// The candidate closest in hue to [target], or null when there are none.
Color? closestAccentCandidate(List<Color> candidates, Color target) {
  if (candidates.isEmpty) {
    return null;
  }
  final targetHue = HSVColor.fromColor(target).hue;
  Color best = candidates.first;
  var bestDistance = double.infinity;
  for (final candidate in candidates) {
    final hue = HSVColor.fromColor(candidate).hue;
    final distance = (hue - targetHue).abs();
    final wrapped = math.min(distance, 360.0 - distance);
    if (wrapped < bestDistance) {
      bestDistance = wrapped;
      best = candidate;
    }
  }
  return best;
}
