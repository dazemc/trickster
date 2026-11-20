import 'dart:async';
import 'dart:io' show stderr;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import 'package:trickster/src/services/bands.dart';

/// The media visualizer's live state: the band levels the pill paints and
/// whether the capture/analysis pair is running.
class VisualizerState extends Equatable {
  const VisualizerState({this.levels = const <double>[], this.active = false});

  /// Normalized 0..1 levels, one per band; empty while stopped.
  final List<double> levels;
  final bool active;

  VisualizerState copyWith({List<double>? levels, bool? active}) {
    return VisualizerState(
      levels: levels ?? this.levels,
      active: active ?? this.active,
    );
  }

  @override
  List<Object?> get props => [active, ...levels];

  Map<String, Object?> toJson() => {
    'active': active,
    'levels': [
      for (final level in levels) double.parse(level.toStringAsFixed(3)),
    ],
  };

  static VisualizerState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('visualizer state must be an object');
    }
    final levels = json['levels'];
    return VisualizerState(
      active: json['active'] == true,
      levels: levels is List
          ? [
              for (final level in levels)
                if (level is num) level.toDouble().clamp(0.0, 1.0) else 0,
            ]
          : const <double>[],
    );
  }
}

sealed class VisualizerEvent extends Equatable {
  const VisualizerEvent();

  @override
  List<Object?> get props => [];
}

/// Mirrors the media bloc's playing flag; the visualizer only runs while
/// something plays.
class VisualizerPlaybackChanged extends VisualizerEvent {
  const VisualizerPlaybackChanged({required this.playing});

  final bool playing;

  @override
  List<Object?> get props => [playing];
}

/// Whether the pill paints the equalizer (mode and orientation decided by
/// the pill); hidden bars run nothing.
class VisualizerVisibilityChanged extends VisualizerEvent {
  const VisualizerVisibilityChanged({required this.visible});

  final bool visible;

  @override
  List<Object?> get props => [visible];
}

class VisualizerLevelsSampled extends VisualizerEvent {
  const VisualizerLevelsSampled(this.levels, {this.generation = 0});

  final List<double> levels;

  /// The analyzer generation that produced these levels; late events from a
  /// stopped or failed run carry an older generation and are ignored.
  final int generation;

  @override
  List<Object?> get props => [generation, ...levels];
}

class _VisualizerFailed extends VisualizerEvent {
  const _VisualizerFailed();
}

class _VisualizerRestartRequested extends VisualizerEvent {
  const _VisualizerRestartRequested();
}

/// Owns the capture and the band analyzer for the media module: active only
/// while a player is playing and the pill paints the visualizer, so the
/// module holds zero timers and zero subscriptions otherwise.
class VisualizerBloc extends Bloc<VisualizerEvent, VisualizerState> {
  VisualizerBloc({
    BandAnalyzer? analyzer,
    this.retryBase = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 30),
  }) : _analyzer = analyzer ?? BandAnalyzer(),
       _retryDelay = retryBase,
       super(const VisualizerState()) {
    on<VisualizerPlaybackChanged>((event, emit) async {
      _playing = event.playing;
      await _sync(emit);
    });
    on<VisualizerVisibilityChanged>((event, emit) async {
      _visible = event.visible;
      await _sync(emit);
    });
    on<VisualizerLevelsSampled>((event, emit) {
      if (event.generation != _generation || _disposed) {
        return;
      }
      if (event.levels.any((level) => level > 0)) {
        _retryDelay = retryBase;
      }
      _trace(event.levels);
      emit(state.copyWith(levels: event.levels));
    });
    on<_VisualizerFailed>((event, emit) {
      if (_disposed) {
        return;
      }
      _generation += 1;
      _restartTimer?.cancel();
      _restartTimer = null;
      _cancelLevels();
      _active = false;
      emit(state.copyWith(active: false, levels: const <double>[]));
      _scheduleRestart();
    });
    on<_VisualizerRestartRequested>((event, emit) async {
      if (_disposed || !_playing || !_visible || _active) {
        return;
      }
      await _start(emit);
    });
    _failuresSubscription = _analyzer.failures.listen(
      (_) => add(const _VisualizerFailed()),
    );
  }

  final BandAnalyzer _analyzer;
  final Duration retryBase;
  final Duration retryMax;
  // Cancelled through _cancelLevels on stop, failure, and close.
  // ignore: cancel_subscriptions
  StreamSubscription<List<double>>? _levelsSubscription;
  late final StreamSubscription<void> _failuresSubscription;
  Timer? _restartTimer;
  Duration _retryDelay;
  var _playing = false;
  var _visible = false;
  var _active = false;
  var _generation = 0;
  var _disposed = false;
  var _lastTrace = DateTime.fromMillisecondsSinceEpoch(0);

  @visibleForTesting
  Duration get retryDelay => _retryDelay;

  Future<void> _sync(Emitter<VisualizerState> emit) async {
    final wanted = _playing && _visible;
    if (!wanted) {
      _restartTimer?.cancel();
      _restartTimer = null;
      if (!_active) {
        return;
      }
      await _stop(emit);
      return;
    }
    if (_active) {
      return;
    }
    _restartTimer?.cancel();
    _restartTimer = null;
    await _start(emit);
  }

  Future<void> _start(Emitter<VisualizerState> emit) async {
    _active = true;
    final generation = ++_generation;
    final bool started;
    try {
      started = await _analyzer.start();
    } on Object catch (error) {
      stderr.writeln('trickster: band analyzer unavailable: $error');
      if (generation == _generation) {
        _active = false;
        emit(state.copyWith(active: false, levels: const <double>[]));
        _scheduleRestart();
      }
      return;
    }
    if (generation != _generation || _disposed) {
      // Stopped or restarted while the monitor was opening.
      if (!_active) {
        await _analyzer.stop();
      }
      return;
    }
    if (!started) {
      _active = false;
      emit(state.copyWith(active: false, levels: const <double>[]));
      _scheduleRestart();
      return;
    }
    _listenLevels(generation);
    emit(state.copyWith(active: true, levels: const <double>[]));
  }

  Future<void> _stop(Emitter<VisualizerState> emit) async {
    _generation += 1;
    _restartTimer?.cancel();
    _restartTimer = null;
    _cancelLevels();
    await _analyzer.stop();
    _active = false;
    emit(state.copyWith(active: false, levels: const <double>[]));
  }

  /// Listens for band levels, replacing any previous listener (none while a
  /// start is in flight; stop clears the field first).
  void _listenLevels(int generation) {
    _cancelLevels();
    _levelsSubscription = _analyzer.levels.listen((levels) {
      if (generation != _generation || _disposed) {
        return;
      }
      add(VisualizerLevelsSampled(levels, generation: generation));
    });
  }

  void _cancelLevels() {
    final subscription = _levelsSubscription;
    _levelsSubscription = null;
    unawaited(subscription?.cancel());
  }

  void _scheduleRestart() {
    if (_disposed || !_playing || !_visible || _active) {
      return;
    }
    _restartTimer?.cancel();
    final delay = _retryDelay;
    final doubled = delay * 2;
    _retryDelay = doubled > retryMax ? retryMax : doubled;
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      if (_disposed) {
        return;
      }
      add(const _VisualizerRestartRequested());
    });
  }

  void _trace(List<double> levels) {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastTrace) < const Duration(seconds: 1)) {
      return;
    }
    _lastTrace = now;
    stderr.writeln(
      'trickster: bands '
      '${levels.map((level) => level.toStringAsFixed(2)).join(' ')}',
    );
  }

  @override
  Future<void> close() async {
    if (_disposed) {
      return super.close();
    }
    _disposed = true;
    _generation += 1;
    _active = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    unawaited(_failuresSubscription.cancel());
    _cancelLevels();
    await _analyzer.dispose();
    return super.close();
  }
}
