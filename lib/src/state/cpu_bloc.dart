import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/cpu.dart';

sealed class CpuEvent extends Equatable {
  const CpuEvent();

  @override
  List<Object?> get props => [];
}

class CpuStarted extends CpuEvent {
  const CpuStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class CpuPaused extends CpuEvent {
  const CpuPaused();
}

class CpuResumed extends CpuEvent {
  const CpuResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class CpuStopped extends CpuEvent {
  const CpuStopped();
}

class CpuSampled extends CpuEvent {
  const CpuSampled(this.sample);

  final CpuSample sample;

  @override
  List<Object?> get props => [sample];
}

class CpuBloc extends Bloc<CpuEvent, CpuSample> {
  CpuBloc({CpuSampler? sampler, CpuSample initial = const CpuSample(null)})
    : _sampler = sampler ?? CpuSampler(),
      super(initial) {
    on<CpuStarted>(_onStarted);
    on<CpuPaused>(_onPaused);
    on<CpuResumed>(_onResumed);
    on<CpuStopped>(_onStopped);
    on<CpuSampled>((event, emit) {
      if (!_stopped) {
        emit(event.sample);
      }
    });
  }

  final CpuSampler _sampler;
  StreamSubscription<CpuSample>? _subscription;
  var _stopped = false;

  void _onStarted(CpuStarted event, Emitter<CpuSample> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(CpuSampled(sample)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(CpuPaused event, Emitter<CpuSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(CpuResumed event, Emitter<CpuSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(CpuStopped event, Emitter<CpuSample> emit) async {
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
