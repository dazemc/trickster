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
    final directory = root;
    if (directory == null || !directory.existsSync()) {
      return const <String>[];
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
    final paths = <String>[];
    for (final file in files) {
      try {
        // Rasterized wallpaper caches are hundreds of megabytes; the daemon's
        // argument files are tiny.
        if (file.lengthSync() > 4096) {
          continue;
        }
        final path = parseWallpaperPath(file.readAsStringSync());
        if (path != null) {
          paths.add(path);
        }
      } on FileSystemException {
        continue;
      }
    }
    return paths;
  }
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
