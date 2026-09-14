import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../services/wallpaper.dart';
import '../theme/wallpaper_accent.dart';

/// Samples the host wallpaper's dominant color while the accent source is
/// `wallpaper`. Disabled controllers hold no watcher, no timer, and no
/// decoded image: the bar starts this only for the setting that needs it.
class WallpaperAccentController extends ChangeNotifier {
  WallpaperAccentController({
    WallpaperCache? cache,
    Future<Color?> Function(Uint8List encoded)? extract,
  }) : _cache = cache ?? WallpaperCache(),
       _extract = extract ?? extractWallpaperAccent;

  static const int _maxCacheEntries = 8;
  static const Duration _debounce = Duration(milliseconds: 300);

  final WallpaperCache _cache;
  final Future<Color?> Function(Uint8List encoded) _extract;

  final Map<String, (int modified, Color? color)> _samples = {};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _timer;
  Color? _color;
  var _enabled = false;
  var _disposed = false;
  var _generation = 0;

  Color? get color => _color;
  bool get enabled => _enabled;

  /// The sampled accent, or null while disabled, pending, or monochrome.
  void update({required bool enabled}) {
    if (_disposed || enabled == _enabled) {
      return;
    }
    _enabled = enabled;
    if (!enabled) {
      _stop();
      _setColor(null);
      return;
    }
    _startWatch();
    _schedule();
  }

  void _startWatch() {
    final root = _cache.root;
    if (root == null || !root.existsSync()) {
      return;
    }
    try {
      _watch = root
          .watch(recursive: true)
          .listen((_) => _schedule(), onError: (_) {});
    } on Object {
      _watch = null;
    }
  }

  void _stop() {
    _watch?.cancel();
    _watch = null;
    _timer?.cancel();
    _timer = null;
    _generation += 1;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_sample()));
  }

  Future<void> _sample() async {
    final generation = ++_generation;
    final paths = _cache.wallpaperPaths();
    Color? color;
    for (final path in paths) {
      color = await _samplePath(path);
      if (color != null) {
        break;
      }
    }
    if (_disposed || generation != _generation || !_enabled) {
      return;
    }
    _setColor(color);
  }

  Future<Color?> _samplePath(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        return null;
      }
      final modified = stat.modified.millisecondsSinceEpoch;
      final cached = _samples[path];
      if (cached != null && cached.$1 == modified) {
        return cached.$2;
      }
      final bytes = await File(path).readAsBytes();
      final color = await _extract(bytes);
      if (_samples.length >= _maxCacheEntries) {
        _samples.remove(_samples.keys.first);
      }
      _samples[path] = (modified, color);
      return color;
    } on Object {
      return null;
    }
  }

  void _setColor(Color? color) {
    if (_color == color) {
      return;
    }
    _color = color;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}

/// Exposes the sampled wallpaper accent to the strip so it rebuilds when the
/// color changes.
class WallpaperAccentScope
    extends InheritedNotifier<WallpaperAccentController> {
  const WallpaperAccentScope({
    required WallpaperAccentController super.notifier,
    required super.child,
    super.key,
  });

  static WallpaperAccentController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WallpaperAccentScope>()
        ?.notifier;
  }
}
