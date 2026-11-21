import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/grim_sampler.dart';
import 'package:trickster/src/services/wallpaper.dart';
import 'package:trickster/src/services/wallpaper_thumbnailer.dart';
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

/// Internal: the debounce elapsed, a cache file changed, or the display set
/// changed. Always samples locally; remote-first callers use
/// [WallpaperAccentRefreshRequested].
class WallpaperAccentSampleRequested extends WallpaperAccentEvent {
  const WallpaperAccentSampleRequested({this.wallpaperChanged = false});

  /// True for a wallpaper-cache event. A grim capture includes the wallpaper
  /// behind the strip, so its per-output cache must be dropped even when the
  /// output geometry is unchanged. A geometry-only refresh keeps the cache and
  /// lets the geometry key decide what to recapture.
  final bool wallpaperChanged;

  @override
  List<Object?> get props => [wallpaperChanged];
}

/// Re-reads the bar's wallpaper state. The settings window emits this when it
/// regains focus, when a settings save lands, or when the wallpaper cache
/// changes. It never runs a periodic poll and never decodes locally while the
/// bar has a usable state.
class WallpaperAccentRefreshRequested extends WallpaperAccentEvent {
  const WallpaperAccentRefreshRequested();
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

/// Reads a wallpaper source without ever allocating more than the byte cap.
/// The stat rejects known-oversized files before opening; reading one byte past
/// the cap catches a file that grew between the stat and the read.
@visibleForTesting
Future<Uint8List?> readWallpaperSource(
  String path, {
  WallpaperSourceLimits limits = const WallpaperSourceLimits(),
}) async {
  try {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > limits.maxBytes) {
      return null;
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(limits.maxBytes + 1);
      return bytes.lengthInBytes > limits.maxBytes ? null : bytes;
    } finally {
      await handle.close();
    }
  } on Object {
    return null;
  }
}

/// Asks another process (the running bar) for its current wallpaper accent
/// state. Settings uses this so it does not decode the same wallpaper twice.
typedef WallpaperAccentRemoteLoader = Future<WallpaperAccentState?> Function();

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

  /// Whether at least one output published a candidate. A remote bar state
  /// with the sampler enabled but no candidates is still pending or
  /// monochrome and is not a substitute for a local fallback.
  bool get hasCandidates => candidates.values.any((list) => list.isNotEmpty);

  /// Whether a remote reply can replace local sampling.
  bool get usable => enabled && hasCandidates;

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

/// Whether a remote wallpaper request reached the bar and what it returned.
enum WallpaperAccentRemoteStatus { unreachable, unusable, usable }

/// One answer from the bar. [WallpaperAccentRemoteStatus.unreachable] starts
/// the local fallback immediately;
/// [WallpaperAccentRemoteStatus.unusable] is a reachable bar that has not
/// finished enabling or sampling yet, so the bloc gives it a bounded settle.
class WallpaperAccentRemoteResult {
  const WallpaperAccentRemoteResult.unreachable()
    : status = WallpaperAccentRemoteStatus.unreachable,
      state = null;

  const WallpaperAccentRemoteResult.unusable([this.state])
    : status = WallpaperAccentRemoteStatus.unusable;

  const WallpaperAccentRemoteResult.usable(this.state)
    : assert(state != null),
      status = WallpaperAccentRemoteStatus.usable;

  final WallpaperAccentRemoteStatus status;

  /// The parsed state even when it is disabled or empty; null when the reply
  /// could not be parsed.
  final WallpaperAccentState? state;

  bool get usable => status == WallpaperAccentRemoteStatus.usable;
  bool get reachable => status != WallpaperAccentRemoteStatus.unreachable;
}

/// A remote probe that also reports whether the bar answered. Settings uses
/// this so a reachable bar that is still catching up gets the bounded settle,
/// while a missing bar falls back to the local sampler immediately.
typedef WallpaperAccentRemoteProbe =
    Future<WallpaperAccentRemoteResult> Function();

/// Samples the host wallpaper's dominant color while the accent source is
/// `wallpaper`. A disabled bloc holds no watcher, no timer, and no decoded
/// image: the bar starts this only for the setting that needs it.
class WallpaperAccentBloc
    extends Bloc<WallpaperAccentEvent, WallpaperAccentState> {
  WallpaperAccentBloc({
    WallpaperCache? cache,
    Future<List<Color>> Function(Uint8List encoded)? extractCandidates,
    Future<List<Color>> Function(String path)? sampleCandidates,
    WallpaperThumbnailer? thumbnailer,
    GrimSampler? grim,
    List<LayerOutput> Function()? outputs,
    ({SystemBarSide side, double thickness}) Function()? strip,
    WallpaperAccentRemoteLoader? remote,
    WallpaperAccentRemoteProbe? remoteProbe,
    List<Duration> remoteSettleDelays = const <Duration>[
      Duration(milliseconds: 100),
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
    ],
    bool watch = true,
    WallpaperAccentState initial = const WallpaperAccentState(),
  }) : _cache = cache ?? WallpaperCache(),
       _extractCandidates = extractCandidates ?? extractWallpaperAccents,
       _samplePathOverride = sampleCandidates,
       _thumbnailer = thumbnailer ?? ProcessWallpaperThumbnailer(),
       _grim = grim ?? GrimSampler(),
       _outputs = outputs,
       _strip = strip,
       _remote = remote,
       _remoteProbe = remoteProbe,
       _remoteSettleDelays = remoteSettleDelays,
       _watchEnabled = watch,
       super(initial) {
    on<WallpaperAccentEnabled>(_onEnabled);
    on<WallpaperAccentSampleRequested>(_onSample);
    on<WallpaperAccentRefreshRequested>(_onRefresh);
  }

  static const int _maxCacheEntries = 8;
  static const int _maxThumbnailBytes = 8 * 1024 * 1024;
  static const Duration _debounce = Duration(milliseconds: 300);

  final WallpaperCache _cache;
  final Future<List<Color>> Function(Uint8List encoded) _extractCandidates;
  final Future<List<Color>> Function(String path)? _samplePathOverride;
  final WallpaperThumbnailer _thumbnailer;
  final GrimSampler _grim;
  final List<LayerOutput> Function()? _outputs;
  final ({SystemBarSide side, double thickness}) Function()? _strip;
  final WallpaperAccentRemoteLoader? _remote;
  final WallpaperAccentRemoteProbe? _remoteProbe;
  final List<Duration> _remoteSettleDelays;
  final bool _watchEnabled;

  /// Screencopy candidates per output, keyed by the strip geometry. A cache
  /// event also includes the wallpaper behind the strip, so it clears this map
  /// even when the geometry is unchanged.
  final Map<String, (String key, List<Color> candidates)> _grimSamples = {};

  final Map<String, (int modified, List<Color>? candidates)> _samples = {};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _timer;

  /// Enable/disable token. A remote or local reply from an older enable must
  /// never land after a disable or a new enable.
  var _generation = 0;

  /// Invalidates one local sampling pass without touching the enable token,
  /// so a remote reply can stop in-flight decode work.
  var _localGeneration = 0;
  var _remoteApplySerial = 0;
  var _localMode = false;
  var _localSampling = false;
  var _localSampleQueued = false;
  var _queuedWallpaperChanged = false;

  /// One status request at a time, and one bounded settle loop at a time.
  /// Refresh events while either is live wait on the same future instead of
  /// opening another socket.
  Future<WallpaperAccentRemoteResult>? _remoteFlight;
  Future<WallpaperAccentRemoteResult>? _settleFlight;

  bool get _hasRemote => _remote != null || _remoteProbe != null;

  Future<void> _onEnabled(
    WallpaperAccentEnabled event,
    Emitter<WallpaperAccentState> emit,
  ) async {
    if (event.enabled == state.enabled) {
      return;
    }
    // A new enable/disable owns the generation; a remote reply from an older
    // request must never overwrite the state that replaced it.
    _stop();
    if (!event.enabled) {
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
    // The cache watcher is useful in both modes: locally it schedules a
    // decode, and while the bar owns the state it only refreshes remote
    // candidates. It never decodes by itself.
    _startWatch();
    if (!_hasRemote) {
      _startLocal();
      return;
    }
    await _refreshRemote(emit);
  }

  /// Re-reads the bar's state. A reachable bar may still be reloading the
  /// document that enabled its sampler, so an unusable reply is retried a
  /// bounded number of times before the local fallback starts.
  Future<void> _refreshRemote(Emitter<WallpaperAccentState> emit) async {
    if (!_hasRemote) {
      _startLocal();
      return;
    }
    final generation = _generation;
    final serial = ++_remoteApplySerial;
    final result = await _startRemoteSettle();
    if (!_remoteCurrent(generation) || serial != _remoteApplySerial) {
      return;
    }
    if (result.usable) {
      // Remote-first always wins, including over a local pass that was about
      // to start or is already decoding.
      _localGeneration += 1;
      _localMode = false;
      _localSampleQueued = false;
      emit(result.state!);
      return;
    }
    if (_localMode) {
      return;
    }
    // A reachable bar that is still resampling keeps the previously usable
    // remote candidates; decoding the same wallpaper here would duplicate the
    // bar's work. A missing bar, or one that never produced a usable state,
    // falls through to the local sampler after the bounded settle.
    if (result.status == WallpaperAccentRemoteStatus.unreachable ||
        !state.hasCandidates) {
      _startLocal();
    }
  }

  /// The fallback path: a bar-less settings app (or a bar with no usable
  /// wallpaper state) owns the decode, thumbnailer, screencopy, and watcher.
  void _startLocal() {
    _startWatch();
    if (!_localMode) {
      _localMode = true;
      // Re-entering local sampling may follow a remote period during which
      // the wallpaper changed. A grim capture is wallpaper-dependent, so the
      // old per-output captures are no longer valid.
      _grimSamples.clear();
    }
    _schedule();
  }

  Future<void> _onSample(
    WallpaperAccentSampleRequested event,
    Emitter<WallpaperAccentState> emit,
  ) async {
    if (!state.enabled) {
      return;
    }
    if (_hasRemote && !_localMode) {
      // A sample request must not start a second decoder while the bar owns
      // the state. Treat it as a refresh instead.
      await _refreshRemote(emit);
      return;
    }
    if (_localSampling) {
      // Coalesce bursts into one follow-up pass; never decode concurrently.
      _localSampleQueued = true;
      _queuedWallpaperChanged =
          _queuedWallpaperChanged || event.wallpaperChanged;
      return;
    }
    if (event.wallpaperChanged) {
      // A cache change invalidates every grim capture even when the output
      // geometry is unchanged: the capture contains the wallpaper behind the
      // strip.
      _grimSamples.clear();
    }
    _localSampling = true;
    final generation = ++_localGeneration;
    try {
      final entries = _cache.wallpaperEntries();
      final candidates = <String, List<Color>>{};
      for (final entry in entries) {
        if (!_localCurrent(generation)) {
          return;
        }
        final sampled = await _samplePath(entry.path);
        if (!_localCurrent(generation)) {
          return;
        }
        if (sampled != null) {
          candidates[entry.output] = sampled;
        }
      }
      for (final output in _outputs?.call() ?? const <LayerOutput>[]) {
        if (!_localCurrent(generation)) {
          return;
        }
        if (candidates.containsKey(output.name)) {
          continue;
        }
        final strip = _strip?.call();
        if (strip == null) {
          break;
        }
        final key =
            '${output.width}x${output.height}-${strip.side.name}-'
            '${strip.thickness}';
        final cached = _grimSamples[output.name];
        if (cached != null && cached.$1 == key) {
          candidates[output.name] = cached.$2;
          continue;
        }
        if (!await _grim.available()) {
          break;
        }
        if (!_localCurrent(generation)) {
          return;
        }
        final sampled = await _grim.sample(
          output: output,
          side: strip.side,
          thickness: strip.thickness,
        );
        if (!_localCurrent(generation)) {
          return;
        }
        _grimSamples[output.name] = (key, sampled);
        candidates[output.name] = sampled;
      }
      if (!_localCurrent(generation)) {
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
    } finally {
      _localSampling = false;
      final queued = _localSampleQueued;
      final queuedWallpaperChanged = _queuedWallpaperChanged;
      _localSampleQueued = false;
      _queuedWallpaperChanged = false;
      if (queued && _localMode && state.enabled && !isClosed) {
        add(
          WallpaperAccentSampleRequested(
            wallpaperChanged: queuedWallpaperChanged,
          ),
        );
      }
    }
  }

  Future<void> _onRefresh(
    WallpaperAccentRefreshRequested event,
    Emitter<WallpaperAccentState> emit,
  ) async {
    if (!state.enabled) {
      return;
    }
    _startWatch();
    if (!_hasRemote) {
      _startLocal();
      return;
    }
    await _refreshRemote(emit);
  }

  Future<WallpaperAccentRemoteResult> _requestRemoteOnce() {
    final existing = _remoteFlight;
    if (existing != null) {
      return existing;
    }
    late final Future<WallpaperAccentRemoteResult> flight;
    flight = _requestRemote().whenComplete(() {
      if (identical(_remoteFlight, flight)) {
        _remoteFlight = null;
      }
    });
    _remoteFlight = flight;
    return flight;
  }

  Future<WallpaperAccentRemoteResult> _requestRemote() async {
    try {
      final probe = _remoteProbe;
      if (probe != null) {
        return await probe();
      }
      final remote = _remote;
      if (remote == null) {
        return const WallpaperAccentRemoteResult.unreachable();
      }
      final remoteState = await remote();
      if (remoteState == null) {
        return const WallpaperAccentRemoteResult.unusable();
      }
      return remoteState.usable
          ? WallpaperAccentRemoteResult.usable(remoteState)
          : WallpaperAccentRemoteResult.unusable(remoteState);
    } on Object {
      return const WallpaperAccentRemoteResult.unreachable();
    }
  }

  Future<WallpaperAccentRemoteResult> _startRemoteSettle() {
    final existing = _settleFlight;
    if (existing != null) {
      return existing;
    }
    final generation = _generation;
    late final Future<WallpaperAccentRemoteResult> flight;
    flight = _runRemoteSettle(generation).whenComplete(() {
      if (identical(_settleFlight, flight)) {
        _settleFlight = null;
      }
    });
    _settleFlight = flight;
    return flight;
  }

  Future<WallpaperAccentRemoteResult> _runRemoteSettle(int generation) async {
    var result = await _requestRemoteOnce();
    for (var attempt = 0; attempt < _remoteSettleDelays.length; attempt += 1) {
      if (!_remoteCurrent(generation) || result.usable || !result.reachable) {
        return result;
      }
      await Future<void>.delayed(_remoteSettleDelays[attempt]);
      if (!_remoteCurrent(generation)) {
        return result;
      }
      result = await _requestRemoteOnce();
    }
    return result;
  }

  bool _remoteCurrent(int generation) =>
      generation == _generation && state.enabled && !isClosed;

  bool _localCurrent(int generation) =>
      generation == _localGeneration && state.enabled && !isClosed;

  void _startWatch() {
    if (!_watchEnabled || _watch != null) {
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
    _localGeneration += 1;
    _remoteApplySerial += 1;
    _localMode = false;
    _localSampleQueued = false;
    _queuedWallpaperChanged = false;
    _settleFlight = null;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      _timer = null;
      if (isClosed || !state.enabled) {
        return;
      }
      add(
        _localMode
            ? const WallpaperAccentSampleRequested(wallpaperChanged: true)
            : const WallpaperAccentRefreshRequested(),
      );
    });
  }

  Future<List<Color>?> _samplePath(String path) async {
    final override = _samplePathOverride;
    if (override != null) {
      return override(path);
    }
    int? modified;
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        return null;
      }
      modified = stat.modified.millisecondsSinceEpoch;
      final cached = _samples[path];
      if (cached != null && cached.$1 == modified) {
        return cached.$2;
      }
      if (stat.size > const WallpaperSourceLimits().maxBytes) {
        final thumbnail = await _thumbnailer.thumbnail(path);
        if (thumbnail == null || thumbnail.lengthInBytes > _maxThumbnailBytes) {
          _remember(path, modified, null);
          return null;
        }
        final candidates = await _extractCandidates(thumbnail);
        _remember(path, modified, candidates);
        return candidates;
      }
      final bytes = await readWallpaperSource(path);
      if (bytes == null) {
        _remember(path, modified, null);
        return null;
      }
      final candidates = await _extractCandidates(bytes);
      _remember(path, modified, candidates);
      return candidates;
    } on Object {
      if (modified != null) {
        _remember(path, modified, null);
      }
      return null;
    }
  }

  void _remember(String path, int modified, List<Color>? candidates) {
    if (_samples.length >= _maxCacheEntries) {
      _samples.remove(_samples.keys.first);
    }
    _samples[path] = (modified, candidates);
  }

  @override
  Future<void> close() async {
    _stop();
    return super.close();
  }
}
