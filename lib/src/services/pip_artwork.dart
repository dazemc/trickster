import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

/// One decoded pip artwork file.
class PipArtwork {
  const PipArtwork({required this.image, required this.vector});

  final ui.Image image;

  /// True when the file compiled through the vector pipeline, so the rail
  /// may recolor it.
  final bool vector;
}

/// Loads a browsed image file, rasterizes it at the pip's display size, and
/// keeps the decoded images in a bounded LRU. Reads and rasterization happen
/// off the frame loop; every failure resolves to null so the rail can fall
/// back to its number glyphs. SVG files are compiled through the vector
/// pipeline, everything else through the engine's image codec.
class PipArtworkCache {
  PipArtworkCache({
    Future<Uint8List?> Function(String path)? read,
    this.dimension = 14,
    this.maxEntries = 16,
    this.maxBytes = 8 << 20,
  }) : _read = read ?? _readFile;

  /// The process-wide cache the rail uses.
  static final PipArtworkCache shared = PipArtworkCache();

  /// Longest side of the decoded square, in logical pixels.
  final int dimension;

  /// Decoded images kept at once; the oldest is dropped past the cap.
  final int maxEntries;

  /// Files larger than this are refused.
  final int maxBytes;

  final Future<Uint8List?> Function(String path) _read;
  final LinkedHashMap<String, Future<PipArtwork?>> _entries =
      LinkedHashMap<String, Future<PipArtwork?>>();

  /// The number of cached entries, for tests and diagnostics.
  int get length => _entries.length;

  /// The decoded artwork for [path], or null while loading or on failure.
  Future<PipArtwork?> load(String path) {
    if (path.isEmpty) {
      return Future<PipArtwork?>.value();
    }
    final existing = _entries.remove(path);
    if (existing != null) {
      _entries[path] = existing;
      return existing;
    }
    final pending = _load(path);
    _entries[path] = pending;
    while (_entries.length > maxEntries) {
      final oldestKey = _entries.keys.first;
      final dropped = _entries.remove(oldestKey)!;
      unawaited(
        dropped.then((artwork) {
          // A decode that lands after eviction must not leak its image.
          artwork?.image.dispose();
        }),
      );
    }
    return pending;
  }

  Future<PipArtwork?> _load(String path) async {
    Uint8List? bytes;
    try {
      bytes = await _read(path);
    } on Object {
      return null;
    }
    if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
      return null;
    }
    return _looksLikeSvg(path, bytes)
        ? _decodeSvg(bytes)
        : _decodeRaster(bytes);
  }

  PipArtwork? _wrap(ui.Image? image, {required bool vector}) =>
      image == null ? null : PipArtwork(image: image, vector: vector);

  Future<PipArtwork?> _decodeSvg(Uint8List bytes) async {
    ui.Picture? picture;
    try {
      final info = await vg.loadPicture(
        SvgStringLoader(utf8.decode(bytes, allowMalformed: true)),
        null,
      );
      picture = info.picture;
      return _wrap(await _rasterize(info.size, picture), vector: true);
    } on Object {
      return null;
    } finally {
      picture?.dispose();
    }
  }

  Future<PipArtwork?> _decodeRaster(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      if (longest <= 0) {
        return null;
      }
      final scale = dimension / longest;
      final width = (descriptor.width * scale).round().clamp(1, dimension);
      final height = (descriptor.height * scale).round().clamp(1, dimension);
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      return _wrap((await codec.getNextFrame()).image, vector: false);
    } on Object {
      return null;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Scales [size] into the pip square and renders the picture.
  ///
  /// `Picture.toImage` rasterizes at the picture's own coordinates; the
  /// drawing is scaled through a recorder so the rendered image is the whole
  /// artwork rather than a cropped corner.
  Future<ui.Image?> _rasterize(ui.Size size, ui.Picture picture) async {
    if (size.width <= 0 || size.height <= 0) {
      return null;
    }
    final longest = size.width > size.height ? size.width : size.height;
    final scale = dimension / longest;
    final width = (size.width * scale).round().clamp(1, dimension);
    final height = (size.height * scale).round().clamp(1, dimension);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale, scale);
    canvas.drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      return await scaled.toImage(width, height);
    } finally {
      scaled.dispose();
    }
  }

  /// Releases every decoded image; the process-wide cache lives until exit,
  /// tests call this to keep the image cache clean.
  void dispose() {
    for (final entry in _entries.values) {
      unawaited(entry.then((artwork) => artwork?.image.dispose()));
    }
    _entries.clear();
  }
}

bool _looksLikeSvg(String path, Uint8List bytes) {
  if (path.toLowerCase().endsWith('.svg')) {
    return true;
  }
  final head = utf8.decode(bytes.take(256).toList(), allowMalformed: true);
  return head.contains('<svg');
}

Future<Uint8List?> _readFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsBytes();
}
