import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/ram.dart';

sealed class RamEvent extends Equatable {
  const RamEvent();

  @override
  List<Object?> get props => [];
}

class RamStarted extends RamEvent {
  const RamStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class RamPaused extends RamEvent {
  const RamPaused();
}

class RamResumed extends RamEvent {
  const RamResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class RamStopped extends RamEvent {
  const RamStopped();
}

class RamSampled extends RamEvent {
  const RamSampled(this.sample);

  final RamSample sample;

  @override
  List<Object?> get props => [sample];
}

class RamBloc extends Bloc<RamEvent, RamSample> {
  RamBloc({RamSampler? sampler, RamSample initial = const RamSample()})
    : _sampler = sampler ?? RamSampler(),
      super(initial) {
    on<RamStarted>(_onStarted);
    on<RamPaused>(_onPaused);
    on<RamResumed>(_onResumed);
    on<RamStopped>(_onStopped);
    on<RamSampled>((event, emit) {
      if (!_stopped) {
        emit(event.sample);
      }
    });
  }

  final RamSampler _sampler;
  StreamSubscription<RamSample>? _subscription;
  var _stopped = false;

  void _onStarted(RamStarted event, Emitter<RamSample> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(RamSampled(sample)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(RamPaused event, Emitter<RamSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(RamResumed event, Emitter<RamSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(RamStopped event, Emitter<RamSample> emit) async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    _sampler.dispose();
  }

  @override
  Future<void> close() async {
    final wasStopped = _stopped;
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    if (!wasStopped) {
      _sampler.dispose();
    }
    return super.close();
  }
}
