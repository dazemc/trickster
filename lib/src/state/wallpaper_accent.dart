import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:trickster/src/services/wallpaper.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

/// Samples the host wallpaper's dominant color while the accent source is
/// `wallpaper`. Disabled controllers hold no watcher, no timer, and no
/// decoded image: the bar starts this only for the setting that needs it.
class WallpaperAccentController extends ChangeNotifier {
  WallpaperAccentController({
    WallpaperCache? cache,
    Future<List<Color>> Function(Uint8List encoded)? extractCandidates,
    Future<List<Color>> Function(String path)? sampleCandidates,
    bool watch = true,
  }) : _cache = cache ?? WallpaperCache(),
       _extractCandidates = extractCandidates ?? extractWallpaperAccents,
       _samplePathOverride = sampleCandidates,
       _watchEnabled = watch;

  static const int _maxCacheEntries = 8;
  static const Duration _debounce = Duration(milliseconds: 300);

  final WallpaperCache _cache;
  final Future<List<Color>> Function(Uint8List encoded) _extractCandidates;
  final Future<List<Color>> Function(String path)? _samplePathOverride;
  final bool _watchEnabled;

  final Map<String, (int modified, List<Color> candidates)> _samples = {};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _timer;
  Color? _color;
  final Map<String, Color?> _accents = <String, Color?>{};
  final Map<String, List<Color>> _candidates = <String, List<Color>>{};
  var _enabled = false;
  var _disposed = false;
  var _generation = 0;

  Color? get color => _color;

  /// The sampled accent per output cache name, in sampler order. The first
  /// non-null entry is the active [color].
  Map<String, Color?> get accents => Map<String, Color?>.unmodifiable(_accents);

  /// The sampled accent for [output], when the wallpaper cache names it.
  Color? accentFor(String output) => _accents[output];

  /// [output]'s wallpaper candidates, strongest first; empty when unsampled.
  List<Color> candidatesFor(String output) =>
      _candidates[output] ?? const <Color>[];

  /// Every potential accent from the active output's wallpaper, strongest
  /// first. The first one is the dominant [color].
  List<Color> get candidates {
    for (final entry in _candidates.entries) {
      if (entry.value.isNotEmpty) {
        return List<Color>.unmodifiable(entry.value);
      }
    }
    return const <Color>[];
  }

  bool get enabled => _enabled;

  /// The sampled accent, or null while disabled, pending, or monochrome.
  void update({required bool enabled}) {
    if (_disposed || enabled == _enabled) {
      return;
    }
    _enabled = enabled;
    if (!enabled) {
      _stop();
      _accents.clear();
      _candidates.clear();
      _setColor(null);
      return;
    }
    _startWatch();
    _schedule();
  }

  void _startWatch() {
    if (!_watchEnabled) {
      return;
    }
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
    final entries = _cache.wallpaperEntries();
    final candidates = <String, List<Color>>{};
    for (final entry in entries) {
      candidates[entry.output] = await _samplePath(entry.path);
    }
    if (_disposed || generation != _generation || !_enabled) {
      return;
    }
    _candidates
      ..clear()
      ..addAll(candidates);
    _accents
      ..clear()
      ..addEntries(
        candidates.entries.map(
          (entry) => MapEntry(
            entry.key,
            entry.value.isEmpty ? null : entry.value.first,
          ),
        ),
      );
    _setColor(
      entries
          .map((entry) => _accents[entry.output])
          .firstWhere((color) => color != null, orElse: () => null),
    );
  }

  Future<List<Color>> _samplePath(String path) async {
    final override = _samplePathOverride;
    if (override != null) {
      return override(path);
    }
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        return const <Color>[];
      }
      final modified = stat.modified.millisecondsSinceEpoch;
      final cached = _samples[path];
      if (cached != null && cached.$1 == modified) {
        return cached.$2;
      }
      final bytes = await File(path).readAsBytes();
      final candidates = await _extractCandidates(bytes);
      if (_samples.length >= _maxCacheEntries) {
        _samples.remove(_samples.keys.first);
      }
      _samples[path] = (modified, candidates);
      return candidates;
    } on Object {
      return const <Color>[];
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
