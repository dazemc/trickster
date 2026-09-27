import 'dart:async';
import 'dart:io' show stderr;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/pipewire.dart';

sealed class MediaEvent extends Equatable {
  const MediaEvent();

  @override
  List<Object?> get props => [];
}

class MediaStarted extends MediaEvent {
  const MediaStarted();
}

class MediaStopped extends MediaEvent {
  const MediaStopped();
}

class MediaSampled extends MediaEvent {
  const MediaSampled(this.playback);

  final MprisPlaybackState playback;

  @override
  List<Object?> get props => [playback];
}

/// Whether the pill currently paints the visualizer (mode and orientation
/// decided by the pill); capture only runs when its levels are seen.
class MediaVisualizerChanged extends MediaEvent {
  const MediaVisualizerChanged({required this.visible});

  final bool visible;

  @override
  List<Object?> get props => [visible];
}

class MediaBloc extends Bloc<MediaEvent, MprisPlaybackState> {
  MediaBloc({
    MediaPlayerService? service,
    MprisPlaybackState? initial,
    PipeWireCapture? capture,
  }) : _service = service ?? MediaPlayerService(),
       _capture = capture ?? PipeWireCapture(),
       super(initial ?? MprisPlaybackState.unavailable()) {
    on<MediaStarted>(_onStarted);
    on<MediaStopped>(_onStopped);
    on<MediaSampled>(_onSampled);
    on<MediaVisualizerChanged>(_onVisualizerChanged);
  }

  final MediaPlayerService _service;
  final PipeWireCapture _capture;
  StreamSubscription<MprisPlaybackState>? _subscription;
  StreamSubscription<PipeWireFrame>? _frameSubscription;
  var _visualizer = false;
  var _capturing = false;
  var _captureGeneration = 0;
  var _frames = 0;
  var _lastFrameLog = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> playPause() => _service.playPause();

  Future<void> next() => _service.next();

  Future<void> previous() => _service.previous();

  /// Starts or stops the monitor stream so it matches what the pill paints:
  /// playing audio with the visualizer visible, nothing otherwise.
  void _syncCapture() {
    final wanted = state.playing && _visualizer;
    if (wanted == _capturing) {
      return;
    }
    _capturing = wanted;
    final generation = ++_captureGeneration;
    unawaited(wanted ? _startCapture(generation) : _stopCapture());
  }

  Future<void> _startCapture(int generation) async {
    _frames = 0;
    _lastFrameLog = DateTime.fromMillisecondsSinceEpoch(0);
    final bool started;
    try {
      started = await _capture.start();
    } on Object catch (error) {
      stderr.writeln('trickster: pipewire capture unavailable: $error');
      if (generation == _captureGeneration) {
        _capturing = false;
      }
      return;
    }
    if (generation != _captureGeneration) {
      // Playback or visibility changed while the monitor was opening: the
      // newest state owns the stream.
      if (!_capturing) {
        await _capture.stop();
      }
      return;
    }
    if (!started) {
      _capturing = false;
      return;
    }
    _listenFrames();
  }

  /// Listens for PCM batches, replacing any previous listener (none while a
  /// start is in flight; stop clears the field first).
  void _listenFrames() {
    unawaited(_frameSubscription?.cancel());
    _frameSubscription = _capture.frames.listen(_onFrame);
  }

  Future<void> _stopCapture() async {
    // The cancel future is not awaited: removing the listener is synchronous,
    // and the stream is stopped below before any late frame could matter.
    final frames = _frameSubscription;
    _frameSubscription = null;
    unawaited(frames?.cancel());
    if (!_capture.isRunning) {
      return;
    }
    await _capture.stop();
    stderr.writeln('trickster: pipewire capture stopped');
  }

  void _onFrame(PipeWireFrame frame) {
    _frames += 1;
    if (_frames == 1) {
      stderr.writeln(
        'trickster: pipewire capture streaming '
        '(${frame.rate} Hz, ${frame.channels} ch)',
      );
      _lastFrameLog = DateTime.now();
      return;
    }
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastFrameLog) < const Duration(seconds: 1)) {
      return;
    }
    _lastFrameLog = now;
    stderr.writeln('trickster: pipewire frames: $_frames');
  }

  Future<void> _onStarted(
    MediaStarted event,
    Emitter<MprisPlaybackState> emit,
  ) async {
    _subscription ??= _service.snapshots.listen(
      (playback) => add(MediaSampled(playback)),
    );
    await _service.start();
  }

  Future<void> _onStopped(
    MediaStopped event,
    Emitter<MprisPlaybackState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onSampled(MediaSampled event, Emitter<MprisPlaybackState> emit) {
    emit(event.playback);
    _syncCapture();
  }

  void _onVisualizerChanged(
    MediaVisualizerChanged event,
    Emitter<MprisPlaybackState> emit,
  ) {
    _visualizer = event.visible;
    _syncCapture();
  }

  @override
  Future<void> close() async {
    _capturing = false;
    _captureGeneration += 1;
    final frames = _frameSubscription;
    _frameSubscription = null;
    unawaited(frames?.cancel());
    await _capture.stop();
    _capture.dispose();
    await _subscription?.cancel();
    _subscription = null;
    await _service.dispose();
    return super.close();
  }
}
