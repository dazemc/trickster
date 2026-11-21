import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/temperature.dart';

sealed class TemperatureEvent extends Equatable {
  const TemperatureEvent();

  @override
  List<Object?> get props => [];
}

class TemperatureStarted extends TemperatureEvent {
  const TemperatureStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class TemperaturePaused extends TemperatureEvent {
  const TemperaturePaused();
}

class TemperatureResumed extends TemperatureEvent {
  const TemperatureResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class TemperatureStopped extends TemperatureEvent {
  const TemperatureStopped();
}

class TemperatureSampled extends TemperatureEvent {
  const TemperatureSampled(this.sample);

  final TemperatureSample sample;

  @override
  List<Object?> get props => [sample];
}

class TemperatureBloc extends Bloc<TemperatureEvent, TemperatureSample> {
  TemperatureBloc({
    TemperatureSampler? sampler,
    TemperatureSample initial = const TemperatureSample(),
  }) : _sampler = sampler ?? TemperatureSampler(),
       super(initial) {
    on<TemperatureStarted>(_onStarted);
    on<TemperaturePaused>(_onPaused);
    on<TemperatureResumed>(_onResumed);
    on<TemperatureStopped>(_onStopped);
    on<TemperatureSampled>((event, emit) {
      if (!_stopped) {
        emit(event.sample);
      }
    });
  }

  final TemperatureSampler _sampler;
  StreamSubscription<TemperatureSample>? _subscription;
  var _stopped = false;

  void _onStarted(TemperatureStarted event, Emitter<TemperatureSample> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(TemperatureSampled(sample)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(TemperaturePaused event, Emitter<TemperatureSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(TemperatureResumed event, Emitter<TemperatureSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(
    TemperatureStopped event,
    Emitter<TemperatureSample> emit,
  ) async {
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
