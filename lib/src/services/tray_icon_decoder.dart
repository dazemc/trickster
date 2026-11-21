import 'dart:collection';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui'
    as ui
    show
        Canvas,
        Codec,
        Image,
        ImageDescriptor,
        ImmutableBuffer,
        Picture,
        PictureRecorder;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_svg/flutter_svg.dart';

import 'package:trickster/src/services/status_notifier_models.dart';

/// Bounds for decoding one tray icon file at strip size.
abstract final class TrayIconLimits {
  static const int preferredIconDimension = 24;
  static const int maxOutputDimension = 64;
  static const int maxIconFileBytes = 8 * 1024 * 1024;
  static const int maxIconFileDimension = 4096;
  static const int maxIconFilePixels = 4 * 1024 * 1024;
}

/// Decodes an icon file at the strip's display size. [ImageByteFormat.rawRgba]
/// is premultiplied, matching [SystemTrayIconPixmap].
Future<SystemTrayIconPixmap?> decodeTrayIconFile(String path) async {
  try {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > TrayIconLimits.maxIconFileBytes) {
      return null;
    }
    final bytes = await File(path).readAsBytes();
    if (_looksLikeSvg(path, bytes)) {
      return await _decodeSvgIcon(bytes);
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > TrayIconLimits.maxIconFileDimension ||
          height > TrayIconLimits.maxIconFileDimension ||
          width * height > TrayIconLimits.maxIconFilePixels) {
        return null;
      }
      final longest = math.max(width, height);
      final scale = TrayIconLimits.preferredIconDimension / longest;
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final longestOutput = math.max(image.width, image.height);
      if (longestOutput > TrayIconLimits.maxOutputDimension) {
        return null;
      }
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      return SystemTrayIconPixmap(
        width: image.width,
        height: image.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  } on Object {
    return null;
  }
}

/// Decodes icon files through one bounded cache.
///
/// The proxy owns one decoder for its icon-path snapshots. A path's in-flight
/// future is shared, failures stay cached as null, and the oldest path is
/// evicted past [maxEntries].
class TrayIconDecoder {
  TrayIconDecoder({
    this.maxEntries = 64,
    Future<SystemTrayIconPixmap?> Function(String path)? decode,
  }) : _decode = decode ?? decodeTrayIconFile;

  final int maxEntries;
  final Future<SystemTrayIconPixmap?> Function(String path) _decode;
  final LinkedHashMap<String, Future<SystemTrayIconPixmap?>> _entries =
      LinkedHashMap<String, Future<SystemTrayIconPixmap?>>();

  /// The number of cached paths, for tests and diagnostics.
  int get length => _entries.length;

  Future<SystemTrayIconPixmap?> decode(String path) {
    final existing = _entries.remove(path);
    if (existing != null) {
      _entries[path] = existing;
      return existing;
    }
    final future = Future<SystemTrayIconPixmap?>.sync(() => _decode(path));
    _entries[path] = future;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return future;
  }

  void dispose() {
    _entries.clear();
  }
}

/// Decodes an icon file exactly as the service does. Exposed for tests.
@visibleForTesting
Future<SystemTrayIconPixmap?> decodeStatusNotifierIconForTesting(String path) =>
    decodeTrayIconFile(path);

bool _looksLikeSvg(String path, List<int> bytes) {
  if (path.toLowerCase().endsWith('.svg')) {
    return true;
  }
  final head = utf8.decode(bytes.take(256).toList(), allowMalformed: true);
  return head.contains('<svg');
}

/// Rasterizes an SVG icon at the strip's display size. The vector compiler
/// runs on its own worker isolate inside flutter_svg; the picture is
/// rendered and flattened here so the rest of the pipeline stays pixel-based.
Future<SystemTrayIconPixmap?> _decodeSvgIcon(List<int> bytes) async {
  final info = await vg.loadPicture(
    SvgStringLoader(utf8.decode(bytes, allowMalformed: true)),
    null,
  );
  try {
    final size = info.size;
    if (size.width <= 0 || size.height <= 0) {
      return null;
    }
    final longest = size.width > size.height ? size.width : size.height;
    final scale = TrayIconLimits.preferredIconDimension / longest;
    final width = (size.width * scale).round();
    final height = (size.height * scale).round();
    if (width <= 0 ||
        height <= 0 ||
        width > TrayIconLimits.maxOutputDimension ||
        height > TrayIconLimits.maxOutputDimension) {
      return null;
    }
    final image = await _scaledPicture(info.picture, width, height, scale);
    if (image == null) {
      return null;
    }
    try {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      return SystemTrayIconPixmap(
        width: image.width,
        height: image.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  } finally {
    info.picture.dispose();
  }
}

/// `Picture.toImage` rasterizes at the picture's own coordinates, so the
/// drawing is scaled through a recorder; without this, icons whose artwork
/// is larger than the pixmap lose everything past the top-left corner.
Future<ui.Image?> _scaledPicture(
  ui.Picture picture,
  int width,
  int height,
  double scale,
) async {
  ui.PictureRecorder? recorder;
  ui.Picture? scaled;
  try {
    recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale, scale);
    canvas.drawPicture(picture);
    scaled = recorder.endRecording();
    return await scaled.toImage(width, height);
  } on Object {
    return null;
  } finally {
    scaled?.dispose();
  }
}
