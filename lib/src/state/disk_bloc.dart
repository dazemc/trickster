import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/disk.dart';

sealed class DiskEvent extends Equatable {
  const DiskEvent();

  @override
  List<Object?> get props => [];
}

class DiskStarted extends DiskEvent {
  const DiskStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class DiskPaused extends DiskEvent {
  const DiskPaused();
}

class DiskResumed extends DiskEvent {
  const DiskResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class DiskStopped extends DiskEvent {
  const DiskStopped();
}

class DiskSampled extends DiskEvent {
  const DiskSampled(this.sample);

  final DiskSample sample;

  @override
  List<Object?> get props => [sample];
}

class DiskBloc extends Bloc<DiskEvent, DiskSample> {
  DiskBloc({DiskSampler? sampler, DiskSample initial = const DiskSample()})
    : _sampler = sampler ?? DiskSampler(),
      super(initial) {
    on<DiskStarted>(_onStarted);
    on<DiskPaused>(_onPaused);
    on<DiskResumed>(_onResumed);
    on<DiskStopped>(_onStopped);
    on<DiskSampled>((event, emit) {
      if (!_stopped) {
        emit(event.sample);
      }
    });
  }

  final DiskSampler _sampler;
  StreamSubscription<DiskSample>? _subscription;
  var _stopped = false;

  void _onStarted(DiskStarted event, Emitter<DiskSample> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(DiskSampled(sample)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(DiskPaused event, Emitter<DiskSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(DiskResumed event, Emitter<DiskSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(DiskStopped event, Emitter<DiskSample> emit) async {
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
