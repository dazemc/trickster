import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/mpris.dart';

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

class MediaBloc extends Bloc<MediaEvent, MprisPlaybackState> {
  MediaBloc({MediaPlayerService? service, MprisPlaybackState? initial})
    : _service = service ?? MediaPlayerService(),
      super(initial ?? MprisPlaybackState.unavailable()) {
    on<MediaStarted>(_onStarted);
    on<MediaStopped>(_onStopped);
    on<MediaSampled>((event, emit) => emit(event.playback));
  }

  final MediaPlayerService _service;
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
    await _service.start();
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
