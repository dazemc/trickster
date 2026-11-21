import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/mpris_worker_proxy.dart';

sealed class MediaEvent extends Equatable {
  const MediaEvent();

  @override
  List<Object?> get props => [];
}

class MediaStarted extends MediaEvent {
  const MediaStarted({this.paused = false});

  /// Whether the seat was already idle when the module was created.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class MediaStopped extends MediaEvent {
  const MediaStopped();
}

class MediaIdleChanged extends MediaEvent {
  const MediaIdleChanged(this.idle);

  final bool idle;

  @override
  List<Object?> get props => [idle];
}

class MediaSampled extends MediaEvent {
  const MediaSampled(this.playback);

  final MprisPlaybackState playback;

  @override
  List<Object?> get props => [playback];
}

class MediaBloc extends Bloc<MediaEvent, MprisPlaybackState> {
  MediaBloc({MediaPlayerClient? service, MprisPlaybackState? initial})
    : _service = service ?? MediaPlayerWorkerProxy(),
      super(initial ?? MprisPlaybackState.unavailable()) {
    on<MediaStarted>(_onStarted);
    on<MediaStopped>(_onStopped);
    on<MediaIdleChanged>(_onIdleChanged);
    on<MediaSampled>((event, emit) => emit(event.playback));
  }

  final MediaPlayerClient _service;
  StreamSubscription<MprisPlaybackState>? _subscription;

  Future<void> playPause() => _service.playPause();

  Future<void> next() => _service.next();

  Future<void> previous() => _service.previous();

  Future<void> _onStarted(
    MediaStarted event,
    Emitter<MprisPlaybackState> emit,
  ) async {
    _subscription ??= _service.snapshots.listen(
      (playback) => add(MediaSampled(playback)),
    );
    await _service.start(paused: event.paused);
  }

  void _onIdleChanged(
    MediaIdleChanged event,
    Emitter<MprisPlaybackState> emit,
  ) {
    if (event.idle) {
      _service.pauseRecovery();
    } else {
      // The one-shot scan can outlive the event; the service's generation
      // guard drops a pause or dispose that lands while it is in flight.
      unawaited(_service.resumeRecovery());
    }
  }

  Future<void> _onStopped(
    MediaStopped event,
    Emitter<MprisPlaybackState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _service.dispose();
    return super.close();
  }
}
