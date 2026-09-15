import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/services/wallpaper.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

/// Events the wallpaper accent sampler answers.
sealed class WallpaperAccentEvent extends Equatable {
  const WallpaperAccentEvent();

  @override
  List<Object?> get props => [];
}

class WallpaperAccentEnabled extends WallpaperAccentEvent {
  const WallpaperAccentEnabled({required this.enabled});

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

/// Internal: the debounce elapsed or a cache file changed.
class _WallpaperAccentSampleRequested extends WallpaperAccentEvent {
  const _WallpaperAccentSampleRequested();
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Color? _color(Object? value) {
  if (value is! String) {
    return null;
  }
  final hex = value.startsWith('#') ? value.substring(1) : value;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xff000000 | parsed);
}

/// The sampled wallpaper accent per output, plus each output's candidate
/// list, strongest first.
class WallpaperAccentState extends Equatable {
  const WallpaperAccentState({
    this.enabled = false,
    this.color,
    this.accents = const <String, Color?>{},
    this.candidates = const <String, List<Color>>{},
  });

  final bool enabled;

  /// The sampled accent, or null while disabled, pending, or monochrome.
  final Color? color;

  /// The sampled accent per output cache name, in sampler order.
  final Map<String, Color?> accents;

  /// Every potential accent per output, strongest first.
  final Map<String, List<Color>> candidates;

  /// The sampled accent for [output], falling back to the first sampled
  /// output when the cache does not name it (a display that shares the
  /// wallpaper publishes no file of its own).
  Color? accentFor(String output) => accents[output] ?? color;

  /// [output]'s wallpaper candidates; falls back to the first sampled
  /// output's list when the cache does not name [output].
  List<Color> candidatesFor(String output) {
    final own = candidates[output];
    if (own != null && own.isNotEmpty) {
      return List<Color>.unmodifiable(own);
    }
    return topCandidates;
  }

  /// Every potential accent from the first sampled output's wallpaper,
  /// strongest first. The first one is the dominant [color].
  List<Color> get topCandidates {
    for (final entry in candidates.entries) {
      if (entry.value.isNotEmpty) {
        return List<Color>.unmodifiable(entry.value);
      }
    }
    return const <Color>[];
  }

  @override
  List<Object?> get props => [
    enabled,
    color,
    ...accents.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ...candidates.entries.map(
      (entry) => Object.hash(entry.key, Object.hashAll(entry.value)),
    ),
  ];

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    if (color case final present?) 'color': _hex(present),
    'accents': {
      for (final entry in accents.entries)
        if (entry.value case final color?) entry.key: _hex(color),
    },
    'candidates': {
      for (final entry in candidates.entries)
        entry.key: [for (final candidate in entry.value) _hex(candidate)],
    },
  };

  static WallpaperAccentState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('wallpaper accent state must be an object');
    }
    final accents = json['accents'];
    final candidates = json['candidates'];
    return WallpaperAccentState(
      enabled: json['enabled'] == true,
      color: _color(json['color']),
      accents: accents is Map<String, dynamic>
          ? {
              for (final entry in accents.entries)
                entry.key: _color(entry.value),
            }
          : const <String, Color?>{},
      candidates: candidates is Map<String, dynamic>
          ? {
              for (final entry in candidates.entries)
                if (entry.value is List)
                  entry.key: [
                    for (final candidate in entry.value as List)
                      ?_color(candidate),
                  ],
            }
          : const <String, List<Color>>{},
    );
  }
}

/// Samples the host wallpaper's dominant color while the accent source is
/// `wallpaper`. A disabled bloc holds no watcher, no timer, and no decoded
/// image: the bar starts this only for the setting that needs it.
class WallpaperAccentBloc
    extends Bloc<WallpaperAccentEvent, WallpaperAccentState> {
  WallpaperAccentBloc({
    WallpaperCache? cache,
    Future<List<Color>> Function(Uint8List encoded)? extractCandidates,
    Future<List<Color>> Function(String path)? sampleCandidates,
    bool watch = true,
  }) : _cache = cache ?? WallpaperCache(),
       _extractCandidates = extractCandidates ?? extractWallpaperAccents,
       _samplePathOverride = sampleCandidates,
       _watchEnabled = watch,
       super(const WallpaperAccentState()) {
    on<WallpaperAccentEnabled>(_onEnabled);
    on<_WallpaperAccentSampleRequested>(_onSample);
  }

  static const int _maxCacheEntries = 8;
  static const Duration _debounce = Duration(milliseconds: 300);

  final WallpaperCache _cache;
  final Future<List<Color>> Function(Uint8List encoded) _extractCandidates;
  final Future<List<Color>> Function(String path)? _samplePathOverride;
  final bool _watchEnabled;

  final Map<String, (int modified, List<Color> candidates)> _samples = {};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _timer;
  var _generation = 0;

  Future<void> _onEnabled(
    WallpaperAccentEnabled event,
    Emitter<WallpaperAccentState> emit,
  ) async {
    if (event.enabled == state.enabled) {
      return;
    }
    if (!event.enabled) {
      _stop();
      emit(const WallpaperAccentState());
      return;
    }
    emit(
      WallpaperAccentState(
        enabled: true,
        color: state.color,
        accents: state.accents,
        candidates: state.candidates,
      ),
    );
    _startWatch();
    _schedule();
  }

  Future<void> _onSample(
    _WallpaperAccentSampleRequested event,
    Emitter<WallpaperAccentState> emit,
  ) async {
    final generation = ++_generation;
    final entries = _cache.wallpaperEntries();
    final candidates = <String, List<Color>>{};
    for (final entry in entries) {
      candidates[entry.output] = await _samplePath(entry.path);
    }
    if (generation != _generation || !state.enabled) {
      return;
    }
    final accents = <String, Color?>{
      for (final entry in candidates.entries)
        entry.key: entry.value.isEmpty ? null : entry.value.first,
    };
    final color = entries
        .map((entry) => accents[entry.output])
        .firstWhere((sampled) => sampled != null, orElse: () => null);
    emit(
      WallpaperAccentState(
        enabled: true,
        color: color,
        accents: accents,
        candidates: candidates,
      ),
    );
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
    _timer = Timer(
      _debounce,
      () => add(const _WallpaperAccentSampleRequested()),
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

  @override
  Future<void> close() async {
    _stop();
    return super.close();
  }
}
