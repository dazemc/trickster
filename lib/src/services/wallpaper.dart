import 'dart:io';

import 'package:flutter/foundation.dart';

/// Locates the host wallpaper from the swww/awww cache. The daemon stores a
/// NUL-separated argument vector per output whose last path token is the
/// displayed image; large files in the cache are rasterized copies, skipped.
class WallpaperCache {
  WallpaperCache({Directory? root}) : root = root ?? defaultRoot();

  final Directory? root;

  static Directory? defaultRoot() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return null;
    }
    for (final name in const ['awww', 'swww']) {
      final directory = Directory('$home/.cache/$name');
      if (directory.existsSync()) {
        return directory;
      }
    }
    return null;
  }

  /// Every wallpaper image currently set, most recently written first.
  List<String> wallpaperPaths() {
    return [for (final entry in wallpaperEntries()) entry.path];
  }

  /// The wallpaper per output, most recently written first. The output name
  /// is the daemon's cache-file name (`HDMI-A-1`); unknown for color-only
  /// setups, which publish no file.
  List<WallpaperEntry> wallpaperEntries() {
    final directory = root;
    if (directory == null || !directory.existsSync()) {
      return const <WallpaperEntry>[];
    }
    final files = directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList(growable: true);
    files.sort((left, right) {
      try {
        return right.statSync().modified.compareTo(left.statSync().modified);
      } on FileSystemException {
        return 0;
      }
    });
    final entries = <WallpaperEntry>[];
    for (final file in files) {
      try {
        // Rasterized wallpaper caches are hundreds of megabytes; the daemon's
        // argument files are tiny.
        if (file.lengthSync() > 4096) {
          continue;
        }
        final path = parseWallpaperPath(file.readAsStringSync());
        if (path != null) {
          entries.add(
            WallpaperEntry(output: file.uri.pathSegments.last, path: path),
          );
        }
      } on FileSystemException {
        continue;
      }
    }
    return entries;
  }
}

/// One output's current wallpaper image.
@immutable
class WallpaperEntry {
  const WallpaperEntry({required this.output, required this.path});

  /// The daemon's cache-file name, usually the connector (`HDMI-A-1`).
  final String output;
  final String path;
}

/// The image path from one daemon cache file, or null for color-only setups.
@visibleForTesting
String? parseWallpaperPath(String cacheFile) {
  for (final token in cacheFile.split('\u0000').reversed) {
    if (token.startsWith('file://')) {
      final uri = Uri.tryParse(token);
      if (uri == null || uri.scheme != 'file' || uri.host.isNotEmpty) {
        continue;
      }
      try {
        return uri.toFilePath();
      } on UnsupportedError {
        continue;
      }
    }
    if (token.startsWith('/')) {
      return token;
    }
  }
  return null;
}
