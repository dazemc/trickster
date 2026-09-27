import 'dart:async';
import 'dart:io' show stderr;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

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
  const VisualizerLevelsSampled(this.levels);

  final List<double> levels;

  @override
  List<Object?> get props => [...levels];
}

/// Owns the capture and the band analyzer for the media module: active only
/// while a player is playing and the pill paints the visualizer, so the
/// module holds zero timers and zero subscriptions otherwise.
class VisualizerBloc extends Bloc<VisualizerEvent, VisualizerState> {
  VisualizerBloc({BandAnalyzer? analyzer})
    : _analyzer = analyzer ?? BandAnalyzer(),
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
      _trace(event.levels);
      emit(state.copyWith(levels: event.levels));
    });
  }

  final BandAnalyzer _analyzer;
  StreamSubscription<List<double>>? _levelsSubscription;
  var _playing = false;
  var _visible = false;
  var _active = false;
  var _generation = 0;
  var _lastTrace = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _sync(Emitter<VisualizerState> emit) async {
    final wanted = _playing && _visible;
    if (wanted == _active) {
      return;
    }
    _active = wanted;
    final generation = ++_generation;
    if (wanted) {
      final bool started;
      try {
        started = await _analyzer.start();
      } on Object catch (error) {
        stderr.writeln('trickster: band analyzer unavailable: $error');
        if (generation == _generation) {
          _active = false;
          emit(state.copyWith(active: false, levels: const <double>[]));
        }
        return;
      }
      if (generation != _generation) {
        // Stopped or restarted while the monitor was opening.
        if (!_active) {
          await _analyzer.stop();
        }
        return;
      }
      if (!started) {
        _active = false;
        emit(state.copyWith(active: false, levels: const <double>[]));
        return;
      }
      _listenLevels();
      emit(state.copyWith(active: true));
      return;
    }
    final subscription = _levelsSubscription;
    _levelsSubscription = null;
    unawaited(subscription?.cancel());
    await _analyzer.stop();
    emit(state.copyWith(active: false, levels: const <double>[]));
  }

  /// Listens for band levels, replacing any previous listener (none while a
  /// start is in flight; stop clears the field first).
  void _listenLevels() {
    unawaited(_levelsSubscription?.cancel());
    _levelsSubscription = _analyzer.levels.listen(
      (levels) => add(VisualizerLevelsSampled(levels)),
    );
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
    _generation += 1;
    _active = false;
    final subscription = _levelsSubscription;
    _levelsSubscription = null;
    unawaited(subscription?.cancel());
    await _analyzer.dispose();
    return super.close();
  }
}
