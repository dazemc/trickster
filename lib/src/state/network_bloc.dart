import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/network.dart';

sealed class NetworkEvent extends Equatable {
  const NetworkEvent();

  @override
  List<Object?> get props => [];
}

class NetworkStarted extends NetworkEvent {
  const NetworkStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class NetworkPaused extends NetworkEvent {
  const NetworkPaused();
}

class NetworkResumed extends NetworkEvent {
  const NetworkResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class NetworkStopped extends NetworkEvent {
  const NetworkStopped();
}

class NetworkSampled extends NetworkEvent {
  const NetworkSampled(this.sample);

  final NetworkSample sample;

  @override
  List<Object?> get props => [sample];
}

class NetworkBloc extends Bloc<NetworkEvent, NetworkSample> {
  NetworkBloc({
    NetworkSampler? sampler,
    NetworkSample initial = const NetworkSample.none(),
  }) : _sampler = sampler ?? NetworkSampler(),
       super(initial) {
    on<NetworkStarted>(_onStarted);
    on<NetworkPaused>(_onPaused);
    on<NetworkResumed>(_onResumed);
    on<NetworkStopped>(_onStopped);
    on<NetworkSampled>((event, emit) {
      if (!_stopped) {
        emit(event.sample);
      }
    });
  }

  final NetworkSampler _sampler;
  StreamSubscription<NetworkSample>? _subscription;
  var _stopped = false;

  void _onStarted(NetworkStarted event, Emitter<NetworkSample> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(NetworkSampled(sample)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(NetworkPaused event, Emitter<NetworkSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(NetworkResumed event, Emitter<NetworkSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(
    NetworkStopped event,
    Emitter<NetworkSample> emit,
  ) async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    await _sampler.dispose();
  }

  @override
  Future<void> close() async {
    final wasStopped = _stopped;
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    if (!wasStopped) {
      await _sampler.dispose();
    }
    return super.close();
  }
}
