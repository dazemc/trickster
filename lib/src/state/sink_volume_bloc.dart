import 'dart:async';
import 'dart:io' show stderr;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:trickster/src/services/volume.dart';

/// The default sink's level as the media module sees it.
class SinkVolumeState extends Equatable {
  const SinkVolumeState({
    this.volume = 0,
    this.muted = false,
    this.active = false,
    this.hasReading = false,
  });

  /// Average channel volume, 0..1.
  final double volume;
  final bool muted;
  final bool active;

  /// Whether a reading arrived; before the first one the level is unknown.
  final bool hasReading;

  SinkVolumeState copyWith({
    double? volume,
    bool? muted,
    bool? active,
    bool? hasReading,
  }) {
    return SinkVolumeState(
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      active: active ?? this.active,
      hasReading: hasReading ?? this.hasReading,
    );
  }

  @override
  List<Object?> get props => [volume, muted, active, hasReading];

  Map<String, Object?> toJson() => {
    'volume': double.parse(volume.toStringAsFixed(3)),
    'muted': muted,
    'active': active,
    'has_reading': hasReading,
  };

  static SinkVolumeState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('sink volume state must be an object');
    }
    final volume = json['volume'];
    return SinkVolumeState(
      volume: volume is num ? volume.toDouble().clamp(0.0, 1.0) : 0,
      muted: json['muted'] == true,
      active: json['active'] == true,
      hasReading: json['has_reading'] == true,
    );
  }
}

sealed class SinkVolumeEvent extends Equatable {
  const SinkVolumeEvent();

  @override
  List<Object?> get props => [];
}

class SinkVolumeStarted extends SinkVolumeEvent {
  const SinkVolumeStarted();
}

class SinkVolumeSampled extends SinkVolumeEvent {
  const SinkVolumeSampled(this.level);

  final SinkVolume level;

  @override
  List<Object?> get props => [level.volume, level.muted];
}

/// A user gesture (the pill's slider) asking for a new level; the write goes
/// to the sink and the watcher echoes it back.
class SinkVolumeSetRequested extends SinkVolumeEvent {
  const SinkVolumeSetRequested(this.volume);

  final double volume;

  @override
  List<Object?> get props => [volume];
}

/// Watches the default sink's volume for the media module; event-driven, so
/// no timers and no polling.
class SinkVolumeBloc extends Bloc<SinkVolumeEvent, SinkVolumeState> {
  SinkVolumeBloc({PipeWireVolume? volume})
    : _volume = volume ?? PipeWireVolume(),
      super(const SinkVolumeState()) {
    on<SinkVolumeStarted>(_onStarted);
    on<SinkVolumeSampled>(_onSampled);
    on<SinkVolumeSetRequested>(_onSetRequested);
  }

  final PipeWireVolume _volume;
  StreamSubscription<SinkVolume>? _subscription;
  var _lastTrace = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _onStarted(
    SinkVolumeStarted event,
    Emitter<SinkVolumeState> emit,
  ) async {
    final bool started;
    try {
      started = await _volume.start();
    } on Object catch (error) {
      stderr.writeln('trickster: sink volume unavailable: $error');
      emit(state.copyWith(active: false));
      return;
    }
    if (!started) {
      emit(state.copyWith(active: false));
      return;
    }
    _subscription ??= _volume.levels.listen(
      (level) => add(SinkVolumeSampled(level)),
    );
    emit(state.copyWith(active: true));
  }

  void _onSampled(SinkVolumeSampled event, Emitter<SinkVolumeState> emit) {
    _trace(event.level.volume);
    emit(
      state.copyWith(
        volume: event.level.volume,
        muted: event.level.muted,
        hasReading: true,
      ),
    );
  }

  void _onSetRequested(
    SinkVolumeSetRequested event,
    Emitter<SinkVolumeState> emit,
  ) {
    final volume = event.volume.clamp(0.0, 1.0);
    emit(state.copyWith(volume: volume));
    unawaited(_volume.set(volume));
  }

  void _trace(double volume) {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastTrace) < const Duration(seconds: 1)) {
      return;
    }
    _lastTrace = now;
    stderr.writeln('trickster: sink volume ${(volume * 100).round()}%');
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _volume.stop();
    _volume.dispose();
    return super.close();
  }
}
