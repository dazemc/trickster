import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Decodes the first frame of an oversized wallpaper outside the Dart heap.
///
/// The direct reader is intentionally capped; a wallpaper that exceeds the byte
/// cap is still useful for its dominant color, so the process path asks an
/// external decoder for one 64 px PNG instead. A missing decoder is a normal
/// fallback to grim or the configured accent.
// The single method is the seam; a concrete class keeps production and test
// implementations named instead of passing an untyped function around.
// ignore: one_member_abstracts
abstract interface class WallpaperThumbnailer {
  Future<Uint8List?> thumbnail(String path);
}

typedef ThumbnailProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

class ProcessWallpaperThumbnailer implements WallpaperThumbnailer {
  ProcessWallpaperThumbnailer({
    ThumbnailProcessRunner? run,
    bool? magickAvailable,
    bool? ffmpegAvailable,
    this.timeout = const Duration(seconds: 20),
    this.maxOutputBytes = 8 * 1024 * 1024,
  }) : _run = run ?? _runProcess,
       _magickAvailable = magickAvailable,
       _ffmpegAvailable = ffmpegAvailable;

  final ThumbnailProcessRunner _run;
  bool? _magickAvailable;
  bool? _ffmpegAvailable;
  final Duration timeout;
  final int maxOutputBytes;

  @override
  Future<Uint8List?> thumbnail(String path) async {
    if (await _hasMagick()) {
      final bytes = await _try('magick', <String>[
        '-limit',
        'memory',
        '64MiB',
        '-limit',
        'map',
        '64MiB',
        '$path[0]',
        '-auto-orient',
        '-resize',
        '64x64',
        'png:-',
      ]);
      if (bytes != null) {
        return bytes;
      }
    }
    if (await _hasFfmpeg()) {
      return _try('ffmpeg', <String>[
        '-v',
        'error',
        '-nostdin',
        '-i',
        path,
        '-frames:v',
        '1',
        '-vf',
        'scale=64:64:force_original_aspect_ratio=decrease',
        '-f',
        'image2pipe',
        '-vcodec',
        'png',
        '-',
      ]);
    }
    return null;
  }

  Future<bool> _hasMagick() async {
    final cached = _magickAvailable;
    if (cached != null) {
      return cached;
    }
    final available = await _probe('magick');
    _magickAvailable = available;
    return available;
  }

  Future<bool> _hasFfmpeg() async {
    final cached = _ffmpegAvailable;
    if (cached != null) {
      return cached;
    }
    final available = await _probe('ffmpeg');
    _ffmpegAvailable = available;
    return available;
  }

  Future<bool> _probe(String executable) async {
    try {
      final result = await _run(executable, const <String>[
        '-version',
      ]).timeout(timeout);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<Uint8List?> _try(String executable, List<String> args) async {
    try {
      final result = await _run(executable, args).timeout(timeout);
      if (result.exitCode != 0) {
        return null;
      }
      final stdout = result.stdout;
      if (stdout is! List<int> ||
          stdout.isEmpty ||
          stdout.length > maxOutputBytes) {
        return null;
      }
      return Uint8List.fromList(stdout);
    } on Object {
      return null;
    }
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> args,
  ) {
    return Process.run(executable, args, stdoutEncoding: null);
  }
}
